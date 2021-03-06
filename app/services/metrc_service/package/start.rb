module MetrcService
  module Package
    class Start < MetrcService::Package::Base
      run_mode :now

      # Valid types can be found on metrc endpoint: /items/v1/categories
      PLANTINGS_PACKAGE_TYPE = 'Immature Plant'.freeze

      def call
        flush_upstream_tasks

        if plant_package?
          create_plant_batch_package
        else
          create_product_package
        end

        success!
      end

      private

      def transaction
        @transaction ||= get_transaction(:start_package_batch)
      end

      def flush_upstream_tasks
        consume_completions.each do |consume|
          source_batch_id = consume.context.dig('source_batch', 'id')
          tasks = upstream_tasks(source_batch_id)

          if tasks.empty?
            log("Source batch #{source_batch_id} has no pending completions!")
          else
            log("Flushing queued completions for source batch #{source_batch_id}")

            TaskRunner.run(*tasks)
          end
        end
      rescue Cannapi::TaskError => e
        raise UpstreamProcessingError, "Failed to process upstream tasks: #{e.message}"
      end

      def upstream_tasks(source_batch_id)
        @integration
          .schedulers
          .for_today(@integration.timezone)
          .where(batch_id: source_batch_id, facility_id: @facility_id)
      end

      def finish_harvests
        payload = finished_harvest_ids.map do |harvest_id|
          { Id: harvest_id, ActualDate: package_date }
        end

        call_metrc(:finish_harvest, payload) unless payload.empty?
      end

      def consumed_harvest_ids
        @consumed_harvest_ids ||= []
      end

      def finished_harvest_ids
        consumed_harvest_ids.select do |harvest_id|
          harvest = call_metrc(:get_harvest, harvest_id)
          harvest['CurrentWeight'].zero?
        end
      end

      def plant_package?
        item_type(skip_validation: true).match?(/Plant/)
      end

      def create_plant_batch_package
        unless tag
          PackageJob.wait_and_perform(:create_plant_batch_package)
          return
        end

        call_metrc(:create_plant_batch_package, create_plant_batch_package_payload)
      end

      def create_plant_batch_package_payload
        consume_completions.map do |consume|
          plant_count = consume.options['consumed_quantity']
          source_batch_id = consume.context.dig('source_batch', 'id')
          plant_batch_label = source_batch(source_batch_id)
          resource_unit = get_resource_unit(consume.options['resource_unit_id'])

          {
            PlantBatch: plant_batch_label,
            Count: plant_count,
            Location: nil,
            Item: resource_unit.item_type,
            Tag: tag,
            PatientLicenseNumber: nil,
            Note: '',
            IsTradeSample: false,
            IsDonation: false,
            ActualDate: package_date
          }
        end
      end

      def create_product_package
        unless batch_tag && tag
          PackageJob.wait_and_perform(:create_product_package)
          return
        end

        call_metrc(:create_harvest_package, create_product_package_payload, testing?)
      end

      def create_product_package_payload
        [{
          Tag: tag,
          Location: zone_name,
          Item: batch.crop_variety,
          UnitOfWeight: unit_of_weight,
          PatientLicenseNumber: nil,
          Note: note,
          IsProductionBatch: false,
          ProductionBatchNumber: nil,
          IsTradeSample: false,
          ProductRequiresRemediation: false,
          RemediateProduct: false,
          RemediationMethodId: nil,
          RemediationDate: nil,
          RemediationSteps: nil,
          ActualDate: package_date,
          Ingredients: consume_completions.map do |consume|
            harvest_ingredient(consume)
          end
        }]
      end

      def testing?
        batch.arbitrary_id =~ /test/i
      end

      def tag
        batch.relationships.dig('barcodes', 'data', 0, 'id')
      end

      def item_type(skip_validation: false)
        validate_item_type!(resource_units&.first&.label) unless skip_validation

        resource_units&.first&.label
      end

      def zone_name
        get_zone(batch.relationships.dig('zone', 'data', 'id')).name
      end

      def unit_of_weight
        validate_resource_units!

        resource_units.first.unit
      end

      def note
        # TODO: retrieve note from completion
      end

      def harvest_ingredient(consume)
        crop_batch = crop_batch_for_consume(consume)
        resource_unit = get_resource_unit(consume.options['resource_unit_id'])
        metrc_harvest = lookup_metrc_harvest(crop_batch.arbitrary_id)

        consumed_harvest_ids << metrc_harvest['Id']

        {
          HarvestId: metrc_harvest['Id'],
          HarvestName: crop_batch.arbitrary_id,
          Weight: consume.options['consumed_quantity'],
          UnitOfWeight: resource_unit.unit
        }
      end

      def crop_batch_for_consume(consume)
        @artemis.get_facility.batch(consume.context.dig('source_batch', 'id'), include: 'barcodes')
      end

      def package_date
        @attributes['start_time']
      end

      # TODO: This is incorrect. We should only be fetching consume completions related to the start.
      def resource_units
        @resource_units ||= consume_completions.map do |completion|
          get_resource_unit(completion.options['resource_unit_id'])
        end
      end

      # TODO: This is incorrect. We should only be fetching consume completions related to the start.
      def consume_completions
        batch_completions.select do |completion|
          completion.action_type == 'consume'
        end
      end

      def validate_resource_units!
        raise InvalidAttributes, 'The package contains resources of multiple types or units. Expected all resources in the package to be the same' \
          unless resource_units.uniq(&:unit).count == 1
      end

      def validate_item_type!(type)
        return if metrc_supported_item_types.include?(type)

        dictionary = DidYouMean::SpellChecker.new(dictionary: metrc_supported_item_types)
        matches = dictionary.correct(type)

        raise InvalidAttributes,
              "The package item type '#{type}' is not supported by Metrc. "\
              "#{matches.present? ? "Did you mean #{matches.map(&:inspect).join(', ')}?" : 'No similar types were found on Metrc.'}"
      end

      def metrc_supported_item_types
        @metrc_supported_item_types ||= begin
                                          metrc_response = @client.get('items', 'categories').body
                                          JSON.parse(metrc_response).map { |entry| entry['Name'] }
                                        end
      end

      def source_batch(batch_id)
        raise InvalidAttributes, "Missing context batch '#{batch_id}'" unless batch_id

        parent_batch = @artemis.get_batch_by_id(batch_id)
        barcodes = parent_batch&.relationships.dig('barcodes', 'data')&.map { |label| label['id'] }

        raise InvalidAttributes, "Missing barcode for batch '#{parent_batch&.arbitrary_id}'" if barcodes.blank?

        matches = barcodes&.select { |label| /[A-Z0-9]{24,24}(-split)?/.match?(label) }

        raise InvalidAttributes, "Expected barcode for batch '#{parent_batch&.arbitrary_id}' to be alphanumeric with 24 characters. Got: #{barcodes.join(', ')}" if matches&.blank?

        matches.sort! { |a, b| a <=> b } if matches&.size > 1

        Common::Utils.normalize_barcode(matches&.first)
      end
    end
  end
end
