
module Delayed
  module Backend
    module Sqs
      class Job
        include ::DelayedJobSqs::Document
        include Delayed::Backend::Base
        extend  Delayed::Backend::Sqs::Actions

        field :priority,    :type => Integer, :default => 0
        field :attempts,    :type => Integer, :default => 0
        field :handler,     :type => String
        field :run_at,      :type => Time
        field :locked_at,   :type => Time
        field :locked_by,   :type => String
        field :failed_at,   :type => Time
        field :last_error,  :type => String
        field :queue,       :type => String

        def initialize(data = {})
          puts "[init] Delayed::Backend::Sqs"
          @msg = nil

          if data.is_a?(AWS::SQS::ReceivedMessage)
            @msg = data
            data = JSON.load(data.body)
          end

          data.symbolize_keys!
          payload_obj = data.delete(:payload_object) || data.delete(:handler)

          @queue_name = data[:queue]      || Delayed::Worker.default_queue_name
          @delay      = data[:delay]      || Delayed::Worker.delay
          @timeout    = data[:timeout]    || Delayed::Worker.timeout
          @expires_in = data[:expires_in] || Delayed::Worker.expires_in
          @attributes = data
          self.payload_object = payload_obj
        end

        def payload_object
          @payload_object ||= YAML.load(self.handler)
        rescue TypeError, LoadError, NameError, ArgumentError => e
          raise DeserializationError,
            "Job failed to load: #{e.message}. Handler: #{handler.inspect}"
        end

        def payload_object=(object)
          if object.is_a? String
            @payload_object = YAML.load(object)
            self.handler = object
          else
            @payload_object = object
            self.handler = object.to_yaml
          end
        end

        def save
          puts "[SAVE] #{@attributes.inspect}"

          if @attributes[:handler].blank?
            raise "Handler missing!"
          end
          payload = JSON.dump(@attributes)

          @msg.delete if @msg

          sqs.queues.named(queue_name).send_message(payload, :delay_seconds  => @delay)
          true
        end

        def save!
          save
        end

        def destroy
          if @msg
            puts "job destroyed! #{@msg.id}\n With attributes #{@attributes.inspect}"
            @msg.delete
          end
        end

        def fail!
          puts "Job failed! #{@msg.inspect}\n With attributes #{@attributes.inspect}"
          destroy
          # v2: move to separate queue
        end

        def update_attributes(attributes)
          attributes.symbolize_keys!
          @attributes.merge attributes
          save
        end

        # No need to check locks
        def lock_exclusively!(*args)
          true
        end

        # No need to check locks
        def unlock(*args)
          true
        end
        
        def reschedule_at
          puts "Executing reschedule_at"
          puts "db_time_now is #{self.class.db_time_now}"
          self.class.db_time_now + (attempts ** 4) + 5
        end

        def reload(*args)
          # reset
          super
        end

        private

        def queue_name
          @queue_name
        end

        def sqs
          ::Delayed::Worker.sqs
        end
      end
    end
  end
end
