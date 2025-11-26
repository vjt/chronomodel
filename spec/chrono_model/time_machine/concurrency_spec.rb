# frozen_string_literal: true

require 'spec_helper'
require 'support/time_machine/structure'

RSpec.describe ChronoModel::TimeMachine do
  include ChronoTest::TimeMachine::Helpers

  describe 'concurrent updates' do
    it 'handles concurrent updates without PG::ExclusionViolation' do
      foo = Foo.create!(name: 'concurrency-test')

      threads_count = 4
      iterations = 10
      errors = []
      mutex = Mutex.new

      threads = Array.new(threads_count) do |i|
        Thread.new do
          iterations.times do |j|
            Foo.transaction do
              record = Foo.find(foo.id)
              record.update!(name: "iteration-#{i}-#{j}")
            end
          rescue StandardError => e
            mutex.synchronize do
              errors << "Thread #{i} Iteration #{j}: #{e.class} - #{e.message}"
            end
          end
        end
      end

      threads.each(&:join)

      if errors.any?
        puts "\nErrors encountered:"
        errors.each { |e| puts e }
      end

      expect(errors).to be_empty
    ensure
      # Clean up: delete the record and its history
      if foo
        foo.destroy
        Foo::History.where(id: foo.id).delete_all
      end
    end
  end

  describe 'concurrent deletions' do
    it 'handles concurrent deletions without error' do
      threads_count = 4
      foos = Array.new(threads_count) { |i| Foo.create!(name: "test-delete-#{i}") }
      foo_ids = foos.map(&:id)
      errors = []
      mutex = Mutex.new

      threads = Array.new(threads_count) do |i|
        Thread.new do
          Foo.transaction do
            foos[i].destroy
          end
        rescue StandardError => e
          mutex.synchronize do
            errors << "Thread #{i}: #{e.class} - #{e.message}"
          end
        end
      end

      threads.each(&:join)

      if errors.any?
        puts "\nErrors encountered:"
        errors.each { |e| puts e }
      end

      expect(errors).to be_empty
      foos.each do |foo|
        expect(Foo.exists?(foo.id)).to be(false)
      end
    ensure
      # Clean up any remaining records and history
      foo_ids&.each do |id|
        Foo.where(id: id).delete_all
        Foo::History.where(id: id).delete_all
      end
    end
  end
end
