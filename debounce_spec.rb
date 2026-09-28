# frozen_string_literal: true

require 'timeout'
require_relative 'debounce'

class FakeScheduler
  Task = Struct.new(:due_at, :block, :cancelled) do
    def cancel
      self.cancelled = true
    end
  end

  def initialize
    @now = 0.0
    @tasks = []
  end

  def schedule(delay_seconds, &block)
    Task.new(@now + delay_seconds, block, false).tap { |task| @tasks << task }
  end

  def advance(seconds)
    @now += seconds
    due = @tasks.select { |t| !t.cancelled && t.due_at <= @now }.sort_by(&:due_at)
    @tasks -= due
    due.each { |t| t.block.call }
  end
end

RSpec.describe Debouncer do
  let(:delay_ms) { 200 }
  let(:scheduler) { FakeScheduler.new }
  let(:calls) { [] }
  let(:fn) { ->(*args) { calls << args } }

  def build(leading: false, trailing: true)
    described_class.new(delay_ms: delay_ms, leading: leading, trailing: trailing, scheduler: scheduler)
  end

  def elapse
    scheduler.advance((delay_ms / 1000.0) + 0.001)
  end

  describe 'a burst of rapid calls (trailing, default)' do
    let(:debounced) { build.debounce(fn) }

    it 'calls fn once, with the arguments of the last call' do
      debounced.call(1)
      debounced.call(2)
      debounced.call(3)
      expect(calls).to be_empty

      elapse
      expect(calls).to eq([[3]])
    end

    it 'does not fire before delay_ms has passed' do
      debounced.call(:a)
      scheduler.advance(0.199)
      expect(calls).to be_empty

      scheduler.advance(0.002)
      expect(calls).to eq([[:a]])
    end

    it 'resets the timer on every new call' do
      debounced.call(:a)
      scheduler.advance(0.15)
      debounced.call(:b)
      scheduler.advance(0.15)
      expect(calls).to be_empty

      scheduler.advance(0.06)
      expect(calls).to eq([[:b]])
    end

    it 'produces separate calls for separate bursts' do
      debounced.call(:first)
      elapse
      debounced.call(:second)
      elapse

      expect(calls).to eq([[:first], [:second]])
    end

    it 'forwards a block to fn' do
      block_result = nil
      block_fn = ->(*, &blk) { block_result = blk.call }

      build.debounce(block_fn).call(:x) { :from_block }
      elapse

      expect(block_result).to eq(:from_block)
    end
  end

  describe 'leading only' do
    let(:debounced) { build(leading: true, trailing: false).debounce(fn) }

    it 'calls fn immediately on the first call' do
      debounced.call(:first)
      expect(calls).to eq([[:first]])
    end

    it 'suppresses the rest of the burst, including after the pause' do
      debounced.call(:first)
      debounced.call(:second)
      debounced.call(:third)
      elapse

      expect(calls).to eq([[:first]])
    end

    it 'keeps suppressing while calls keep resetting the timer' do
      debounced.call(:first)
      scheduler.advance(0.15)
      debounced.call(:second)
      scheduler.advance(0.15)
      debounced.call(:third)

      expect(calls).to eq([[:first]])
    end

    it 'allows a new leading call in the next burst' do
      debounced.call(:burst1)
      elapse
      debounced.call(:burst2)

      expect(calls).to eq([[:burst1], [:burst2]])
    end
  end

  describe 'leading + trailing' do
    let(:debounced) { build(leading: true, trailing: true).debounce(fn) }

    it 'a single call fires only once (leading)' do
      debounced.call(:solo)
      elapse

      expect(calls).to eq([[:solo]])
    end

    it 'several calls fire leading with the first args and trailing with the last' do
      debounced.call(:first)
      debounced.call(:middle)
      debounced.call(:last)
      expect(calls).to eq([[:first]])

      elapse
      expect(calls).to eq([[:first], [:last]])
    end

    it 'starts a new leading call after the burst has ended' do
      debounced.call(:a)
      debounced.call(:b)
      elapse
      debounced.call(:c)

      expect(calls).to eq([[:a], [:b], [:c]])
    end
  end

  describe 'constructor' do
    it 'rejects leading: false and trailing: false at once' do
      expect { build(leading: false, trailing: false) }.to raise_error(ArgumentError)
    end
  end

  describe '#dispose' do
    it 'cancels a pending trailing call' do
      debouncer = build
      debouncer.debounce(fn).call(:cancelled)
      debouncer.dispose
      elapse

      expect(calls).to be_empty
    end

    it 'starts a fresh burst on the next call (leading fires again)' do
      debouncer = build(leading: true, trailing: true)
      debounced = debouncer.debounce(fn)

      debounced.call(:a)
      debouncer.dispose
      debounced.call(:b)

      expect(calls).to eq([[:a], [:b]])
    end

    it 'is safe to call with no active timer' do
      expect { build.dispose }.not_to raise_error
    end
  end

  describe 'RealScheduler (real time)' do
    it 'calls fn asynchronously after delay_ms with the last args' do
      results = Queue.new
      debounced = described_class.new(delay_ms: 30).debounce(->(*args) { results << args })

      debounced.call(:x)
      debounced.call(:y)

      expect(Timeout.timeout(2) { results.pop }).to eq([:y])
    end

    it 'does not call fn after dispose' do
      results = Queue.new
      debouncer = described_class.new(delay_ms: 20)
      debouncer.debounce(->(*args) { results << args }).call(:x)
      debouncer.dispose
      sleep(0.1)

      expect(results).to be_empty
    end

    it 'survives rapid calls racing with a firing timer' do
      results = Queue.new
      debounced = described_class.new(delay_ms: 5).debounce(->(*args) { results << args })

      Timeout.timeout(5) do
        100.times do |i|
          debounced.call(i)
          sleep(0.001)
        end
        results.pop
      end
    end
  end
end
