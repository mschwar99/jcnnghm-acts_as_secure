module ActiveRecord; module Acts; end; end

module ActiveRecord::Acts::ActsAsSecure

  require 'yaml'

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods

    def acts_as_secure(options = {})
      parse_options!(options)
      add_callbacks
      extend(ActsAsSecureClassMethods)
      send(:include, InstanceMethods)
    end

  private

    def parse_options!(options)
      @secure_except = unsecure_columns(options.delete(:except))
      @secure_storage_type = options.delete(:storage_type) || :binary
      @secure_crypto_provider = options.delete(:crypto_provider)
      fail("Unknown option(s): #{ options.keys.join(', ') }") unless options.empty?
    end

    def add_callbacks
      before_save :encrypt_secure_columns
      after_save :decrypt_secure_columns
      after_find :decrypt_secure_columns
    end

    def unsecure_columns(*names)
      names.flatten.collect(&:to_s)
    end

    module ActsAsSecureClassMethods

      def inherited(sub)

        [:secure_except, :secure_storage_type, :secure_crypto_provider].each do |p|
          sub.instance_variable_set("@#{ p }", instance_variable_get("@#{ p }"))
        end

        super

      end

      def with_crypto_provider(provider)
        begin
          original_provider = @secure_crypto_provider
          @secure_crypto_provider = provider
          yield
        ensure
          @secure_crypto_provider = original_provider
        end
      end

      def secure_columns
        columns.reject { |col| (col.type != @secure_storage_type) || @secure_except.include?(col.name) }
      end

      def secure_crypto_provider
        @secure_crypto_provider
      end

    end

    module InstanceMethods

      def encrypt_secure_columns
        self.class.secure_columns.each do |col|
          self[col.name] = secure_encrypt(self[col.name])
        end
      end

      def decrypt_secure_columns
        @encrypted_attributes = {}
        self.class.secure_columns.each do |col|
          if ActiveRecord::VERSION::MAJOR == 4 && ActiveRecord::VERSION::MINOR >= 2
            before_type_cast = send("#{ col.name }")#read_attribute_before_type_cast(col.name)
          else
            before_type_cast = send("#{ col.name }_before_type_cast")
          end
          @encrypted_attributes[col.name] = before_type_cast
          self[col.name] = secure_decrypt(before_type_cast) unless self[col.name].nil?
        end
      end

      def read_attribute_before_decryption(attr_name)
        if @encrypted_attributes[attr_name.to_s].nil?
          self[attr_name]
        else
          @encrypted_attributes[attr_name.to_s]
        end
      end

    private

      def secure_encrypt(arg)
        secure_crypto_provider.encrypt(arg.to_yaml)
      end

      def secure_decrypt(arg)
        begin
          YAML.load(secure_crypto_provider.decrypt(arg))
        rescue Exception => ex
          raise "Failed to decode the field. Incorrect key?"
        end
      end

      def secure_crypto_provider
        self.class.secure_crypto_provider || fail('No crypto provider defined')
      end

    end

  end

end

ActiveRecord::Base.send(:include, ActiveRecord::Acts::ActsAsSecure)