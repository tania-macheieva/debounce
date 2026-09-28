# frozen_string_literal: true

require 'monitor'

class Debouncer
  class RealScheduler
    class Handle
      def initialize(delay, &block)
        @mutex = Mutex.new
        @cv = ConditionVariable.new
        @cancelled = false

        @thread = Thread.new do
          wait(delay)
          block.call unless cancelled?
        end
      end

      def cancel
        @mutex.synchronize do
          @cancelled = true
          @cv.signal
        end
      end

      private

      def cancelled?
        @mutex.synchronize { @cancelled }
      end

      def wait(delay)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay
        @mutex.synchronize do
          until @cancelled
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            @cv.wait(@mutex, remaining)
          end
        end
      end
    end

    def schedule(delay_seconds, &block)
      Handle.new(delay_seconds, &block)
    end
  end

  def initialize(delay_ms:, leading: false, trailing: true, scheduler: RealScheduler.new)
    raise ArgumentError, 'at least one of leading/trailing must be true' unless leading || trailing

    @delay_seconds = delay_ms / 1000.0
    @leading = leading
    @trailing = trailing
    @scheduler = scheduler

    @lock = Monitor.new
    reset_burst!
  end

  def debounce(fn)
    ->(*args, &block) { invoke(fn, args, block) }
  end

  def dispose
    @lock.synchronize do
      @timer&.cancel
      reset_burst!
    end
  end

  private

  def invoke(fn, args, block)
    call_now = false

    @lock.synchronize do
      @timer&.cancel
      @calls += 1
      @last_call = [args, block]
      call_now = @leading && @calls == 1

      handle = nil
      handle = @scheduler.schedule(@delay_seconds) { quiet_period_elapsed(fn, handle) }
      @timer = handle
    end

    fn.call(*args, &block) if call_now
  end

  def quiet_period_elapsed(fn, handle)
    call_now = false
    args = block = nil

    @lock.synchronize do
      return unless @timer.equal?(handle)

      call_now = @trailing && (!@leading || @calls > 1)
      args, block = @last_call
      reset_burst!
    end

    fn.call(*args, &block) if call_now
  end

  def reset_burst!
    @timer = nil
    @calls = 0
    @last_call = nil
  end
end
