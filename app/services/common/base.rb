require_relative './base_service_action'

module Common
  class Base < BaseServiceAction
    RETRYABLE_ERRORS = [
      Net::HTTPRetriableError,
    ].freeze

    attr_reader :artemis

    delegate :seeding_unit, to: :batch
    delegate :get_batch, :get_items, :get_zone,
             :get_child_completions,
             :get_related_completions,
             to: :artemis

    def initialize(ctx, integration, batch = nil)
      @ctx = ctx
      @relationships = ctx[:relationships]
      @completion_id = ctx[:id]
      @integration = integration
      @attributes  = ctx[:attributes]
      @facility_id = @relationships&.dig(:facility, :data, :id)
      @batch_id = @relationships&.dig(:batch, :data, :id)
      @artemis  = ArtemisService.new(@integration.account, @batch_id, @facility_id)
      @client = build_client
      @batch  = batch if batch

      super
    end

    def run(*)
      super
    rescue BatchCropInvalid
      log("Failed: Crop is not #{@integration.vendor_module::CROP} but #{batch.crop}. Batch ID #{@batch_id}, completion ID #{@completion_id}")
      fail!
    rescue InvalidBatch, InvalidOperation => e
      log(e.message)
      fail!
    rescue ServiceActionFailure => e
      log("Failed: batch ID #{@batch_id}, completion ID #{@completion_id}; #{e.inspect}", :error)
      fail!(transaction)
    end

    private

    attr_reader :client

    def build_client
      raise NotImplementedError
    end

    protected

    def before
      log("Started: batch ID #{@batch_id}, completion ID #{@completion_id}")

      super

      return if @batch_id.nil?

      validate_batch!
      validate_seeding_unit!
    end

    def state
      config[:state_map].fetch(@integration.state.upcase.to_sym, @integration.state)
    end

    def get_transaction(name, metadata = @attributes)
      Transaction.find_or_create_by(
        vendor: :metrc, account: @integration.account, integration: @integration,
        batch_id: @batch_id, completion_id: @completion_id, type: name
      ) do |transaction|
        transaction.metadata = metadata
      end
    end

    def get_resource_unit(id, include: nil)
      resource_unit = @artemis.get_resource_unit(id, include: include)
      map_resource_unit(resource_unit)
    end

    def get_resource_units(include: nil)
      @artemis.get_resource_units(include: include).map do |resource_unit|
        map_resource_unit(resource_unit)
      end
    end

    def batch
      @batch ||= get_batch
    end

    def batch_tag
      return @tag if @tag

      barcodes = batch.relationships.dig('barcodes', 'data')&.map { |label| label['id'] }

      matches = barcodes&.select { |label| /[A-Z0-9]{24,}/.match?(label) }

      raise InvalidAttributes, "Missing barcode for batch '#{batch.arbitrary_id}'" if barcodes.blank?
      raise InvalidAttributes, "Expected barcode for batch '#{batch.arbitrary_id}' to be alphanumeric with 24 characters. Got: #{barcodes.join(', ')}" if matches.blank?

      return @tag = matches&.first unless matches&.size > 1

      matches.sort! { |a, b| a <=> b }

      @tag = matches&.first
    end

    def validate_batch!
      raise BatchCropInvalid unless batch.crop == @integration.vendor_module::CROP
    end

    def validate_seeding_unit!
      return if ['preprinted', 'none', nil].include?(seeding_unit.item_tracking_method)

      raise InvalidBatch, "Failed: Seeding unit is not valid for Metrc #{seeding_unit.item_tracking_method}. " \
        "Batch ID #{@batch_id}, completion ID #{@completion_id}"
    end

    def config
      @config ||= Rails.application.config_for('providers/metrc')
    end

    # Possible statuses: active, removed, archived
    def completion_status
      @attributes['status']
    end

    def resource_completions_by_unit_type(unit_type)
      resource_unit_id = resource_unit(unit_type).id

      batch
        .completions
        .select { |completion| %w[process generate].include?(completion.action_type) }
        .select { |completion| completion.options['resource_unit_id'] == resource_unit_id }
    end
  end
end