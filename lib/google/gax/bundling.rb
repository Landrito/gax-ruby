# Copyright 2016, Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#     * Neither the name of Google Inc. nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

module Google
  module Gax
    MILLIS_PER_SECOND = 1000.0

    # rubocop:disable Metrics/ClassLength

    # Coordinates the execution of a single bundle.
    #
    # @attribute [r] bundle_id
    #   @return [String] The id of this bundle.
    # @attribute [r] bundled_field
    #   @return [String] The field used to create the bundled request.
    # @attribute [r] subresponse_field
    #   @return [String] Optional field used to demultiplex responses.
    class Task
      attr_reader :bundle_id, :bundled_field,
                  :subresponse_field

      # rubocop:disable Metrics/ParameterLists

      # @param api_call [Proc] Used to make an api call when the task is run.
      # @param bundle_id [String] The id of this bundle.
      # @param bundled_field [String] The field used to create the
      #     bundled request.
      # @param bundling_request [Object] The request to pass as the arg to
      #     the api_call.
      # @param kwargs [Hash] The keyword arguments passed to the api_call.
      # @param subresponse_field [String] Optional field used to demultiplex
      #     responses.
      def initialize(api_call,
                     bundle_id,
                     bundled_field,
                     bundling_request,
                     kwargs,
                     subresponse_field: nil)
        @api_call = api_call
        @bundle_id = bundle_id
        @bundled_field = bundled_field
        @bundling_request = bundling_request
        @kwargs = kwargs
        @subresponse_field = subresponse_field
        @in_deque = []
        @event_deque = []
      end

      # The number of bundled elements in the repeated field.
      # @return [Numeric]
      def element_count
        sum = 0
        @in_deque.each { |elts| sum += elts.count }
        sum
      end

      # The size of the request in bytes of the bundled field elements.
      # @return [Numeric]
      def request_bytesize
        sum = 0
        @in_deque.each do |elts|
          elts.each do |e|
            sum += e.to_s.bytesize
          end
        end
        sum
      end

      # Call the task's api_call.
      #
      # The task's func will be called with the bundling requests function.
      def run
        return if in_deque.count == 0
        request = @bundling_request
        request[bundled_field] = @in_deque.flatten

        if @subresponse_field
          run_with_subresponses(request, @subreponse_field, @kwargs)
        else
          run_with_no_subresponse(request, @kwargs)
        end
      end

      # Disable this since the api_call may raise any type of exception.
      # rubocop:disable Lint/RescueException

      def run_with_no_subresponse(request, kwargs)
        response = @api_call.call(request, **kwargs)
        @event_deque.each do |event|
          event.result = response
          event.set
        end
      rescue Exception => err
        @event_deque.each do |event|
          event.result = err
          event.set
        end
      ensure
        @in_deque.clear
        @event_deque.clear
      end

      def run_with_subresponses(request, subresponse_field, kwargs)
        response = @api_call.call(request, **kwargs)
        in_sizes_sum = 0
        in_deque.each { |elts| in_sizes_sum += elts.count }
        all_subresponses = response[subresponse_field]
        if all_subresponses.count != in_sizes_sum
          "cannot demultiplex the bundled response, got
            #{all_subresonses.count} subresponses; want #{in_sizes_sum},
            each bundled request will receive all responses"
        end
        @event_deque.each do |event|
          event.result = response
          event.set
        end
      rescue Exception => err
        @event_deque.each do |event|
          event.result = err
          event.set
        end
      ensure
        @in_deque.clear
        @event_deque.clear
      end

      # This adds elements to the tasks.
      #
      # @param elts [Array<Object>] An array of elements that can be appended
      #     to the tasks bundle_field.
      # @return [Event] An Event that can be used to wait on the response.
      def extend(elts)
        elts = [*elts]
        in_deque.push(elts)
        event = event_for(elts)
        event_deque.append(event)
        event
      end

      # Creates an Event that is set when the bundle with elts is sent.
      #
      # @param elts [Array<Object>] An array of elements that can be appended
      #     to the tasks bundle_field.
      # @return [Event] An Event that can be used to wait on the response.
      def event_for(elts)
        event = new Event
        event.canceller = canceller_for(elts, event)
        event
      end

      # Creates a cancellation proc that removes elts.
      #
      # The proc returns true if all elements were successfully removed from
      # in_deque and event_deque.
      #
      # @param elts [Array<Object>] An array of elements that can be appended
      #     to the tasks bundle_field.
      # @param [Event] An Event that can be used to wait on the response.
      # @return [Proc] The canceller that when called removes the elts
      #     and events.
      def canceller_for(elts, event)
        proc do
          event_index = event_deque.find_index(event)
          in_index = in_deque.find_inbdex(elts)
          if event_deque.delete_at(event_index).nil? ||
             in_deque.delete_at(in_index).nil?
            return false
          end
          return true
        end
      end

      private_class_method :run_with_no_subresponse,
                           :run_with_subresponses,
                           :event_for, :cancellor_for
    end

    # Organizes bundling for an api service that requires it.
    class Executor
      UPDATE_THREADS_RATE = 60

      # @param [BundleOptions]configures strategy this instance
      #     uses when executing bundled functions.
      def initialize(options)
        @options = options
        @tasks = {}

        # Use a Monitor in order to have the mutex behave like a reentrant lock.
        @tasks_lock = Monitor.new

        # Keep track of the threads that are spawned in order to ensure the
        # api call is made before the main thread dies.
        @threads = {}

        # The class may spawn many threads. This thread will remove any dead
        # threads from @threads.
        @threads_monitor = Thread.new do
          loop do
            sleep UPDATE_THREADS_RATE
            @tasks_lock.synchronize do
              @threads.each do |bundle_id, thread|
                @threads.delete(bundle_id) unless thread.alive?
              end
            end
          end
        end
      end

      # Schedules bundle_desc of bundling_request as part of
      # bundle id.
      #
      # @param api_call [Proc] Used to make an api call when the task is run.
      # @param bundle_id [String] The id of this bundle.
      # @param bundle_desc [BundleDescriptor]  describes the structure of the
      #     bundled call.
      # @param bundling_request [Object] The request to pass as the arg to
      #     the api_call.
      # @param kwargs [Hash] The keyword arguments passed to the api_call.
      # @return [Event] An Event that can be used to wait on the response.
      def schedule(api_call, bundle_id, bundle_desc,
                   bundling_request, kwargs: {})
        bundle = bundle_for(api_call, bundle_id, bundle_desc,
                            bundling_request, kwargs)
        elts = bundling_request[bundle_desc.bundled_field]
        event = bundle.extend(elts)

        count_threshold = @options.element_count_threshold
        if count_threshold > 0 && bundle.element_count >= count_threshold
          run_now(bundle.bundle_id)
        end

        size_threshold = @options.request_byte_threshold
        if size_threshold > 0 && bundle.request_bytesize >= size.threshold
          run_now(bundle.bundle_id)
        end

        event
      end

      def bundle_for(api_call, bundle_id, bundle_desc, bundling_request, kwargs)
        @tasks_lock.synchronize do
          return @tasks[bundle_id] if @tasks.key?(bundle_id)
          bundle = Task.new(api_call, bundle_id, bundle_desc.bundled_field,
                            bundling_request, kwargs,
                            bundle_desc.subresponse_field)
          delay_threshold = @options.delay_threshold
          run_later(bundle, delay_threshold) if delay_threshold > 0
          @tasks[bundle_id] = bundle
          return bundle
        end
      end

      def run_later(bundle, delay_threshold)
        @tasks_lock.synchronize do
          Thread.new do
            sleep(delay_threshold / MILLIS_PER_SECOND)
            run_now(bundle.bundle_id)
          end
        end
      end

      def run_now(bundle_id)
        @tasks_lock.synchronize do
          if @tasks.key?(bundle_id)
            @task = @tasks.delete(bundle_id)
            @task.run
          end
        end
      end

      def close
        @threads.each do |bundle_id, _|
          @tasks_lock.synchronize do
            run_now(bundle_id)
          end
        end
      end

      private_class_method :bundle_for, :run_later, :run_now
    end
  end

  # Container for a thread adding the ability to cancel, check if set, and
  # get the result of the thread.
  class Event
    attr_accessor :canceller, :result

    def initialize
      @canceller = nil
      @result = nil
      @set = False
      @mutex = Mutex.new
    end

    # Checks to see if the event has been set. A set Event signals that there is
    # data in @result.
    # @return [Boolean] Whether the event has been set.
    def set?
      @set
    end

    # Signifies that the event has been set and that there is data in @result.
    def set
      @mutex.synchronize do
        @set = True
      end
    end

    # Resets the Event to not being set and clears the @result.
    def clear
      @mutex.synchronize do
        @result = nil
        @set = False
      end
    end

    # Invokes the cancellation function provided.
    def cancel
      @mutex.synchronize do
        cancelled = canceller.call unless canceller.nil?
        @thread.kill if cancelled
        cancelled
      end
    end
  end
end
