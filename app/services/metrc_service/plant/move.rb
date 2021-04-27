module MetrcService
  module Plant
    class Move < Base
      DEFAULT_MOVE_STEP = :change_growth_phase
      WET_WEIGHT = /wet weight/i.freeze

      # CA only allows flowering growth phase.
      # Because artemis stages and zones are tightly coupled, sometimes plants will be move into barcoded flowering stage but still be in a "veg" zone
      CA_GROWTH_PHASE_MAP = {
        vegetative: 'Flowering',
        flowering: 'Flowering'
      }.freeze

      MA_GROWTH_PHASE_MAP = {
        vegetative: 'Vegetative',
        flowering: 'Flowering'
      }.freeze

      MO_GROWTH_PHASE_MAP = {
        vegetative: 'Vegetative',
        flowering: 'Flowering'
      }.freeze

      STATE_GROWTH_PHASE_MAP = {
        ca: CA_GROWTH_PHASE_MAP,
        ma: MA_GROWTH_PHASE_MAP,
        mo: MO_GROWTH_PHASE_MAP
      }.freeze

      def call
        if next_step_name.nil?
          skip!
        else
          log("Next step: #{next_step_name}. Batch ID #{@batch_id}, completion ID #{@completion_id}")
          send(next_step_name)
          success!
        end
      end

      def transaction
        @transaction ||= get_transaction(:move_batch, @attributes)
      end

      def prior_move
        previous_move = batch_completions.select { |comp| comp.action_type == 'move' && comp.id.to_i < @completion_id.to_i }
                                         .max_by { |comp| [comp.start_time, comp.id] }

        return if previous_move.nil?

        # calling get_completion here will ensure relationships are side loaded.
        get_completion(previous_move.id)
      end
      memoize :prior_move

      def start_completion
        start = batch_completions.find { |comp| comp.action_type == 'start' || comp.action_type == 'split_start' }
        return if start.nil?

        # calling get_completion here will ensure relationships are side loaded.
        get_completion(start&.id)
      end
      memoize :start_completion

      private

      def within_phases?(zone_name, expected_zones)
        return false unless zone_name && expected_zones

        expected_zones.any? { |phase| zone_name.include?(phase) }
      end

      def next_step_name
        previous_completion = prior_move || start_completion
        step = next_step(previous_completion, current_completion)

        return unless step

        metadata = transaction.metadata
        substage = get_substage
        metadata[:sub_stage] = substage
        metadata[:next_step] = step
        transaction.update(metadata: metadata)

        step
      end
      memoize :next_step_name

      def next_step(previous_completion = nil, current_completion = nil) # rubocop:disable Metrics/PerceivedComplexity
        return DEFAULT_MOVE_STEP if previous_completion.nil? || current_completion.nil? || current_completion.action_type == 'start'
        return nil if move_harvest?

        previous_growth_phase = growth_phase_for_completion(previous_completion)
        new_growth_phase = growth_phase_for_completion(current_completion)

        return DEFAULT_MOVE_STEP if previous_growth_phase.nil? || new_growth_phase.nil?

        # Yeah, I don't like this either.
        previous_completion_had_barcodes = items_have_barcodes?(previous_completion.included&.dig(:seeding_units)&.first&.item_tracking_method)
        current_completion_has_barcodes  = items_have_barcodes?(current_completion.included&.dig(:seeding_units)&.first&.item_tracking_method)
        has_no_barcodes = !previous_completion_had_barcodes && !current_completion_has_barcodes
        moved_to_barcodes = !previous_completion_had_barcodes && current_completion_has_barcodes
        already_had_barcodes = previous_completion_had_barcodes && current_completion_has_barcodes

        # TODO: create a separate split service to handle barcoded and non-barcoded splits
        if current_completion.action_type == 'split'
          return :move_plants if already_had_barcodes

          # for now we skip splits when no barcodes are available
          return nil
        end

        return :move_plant_batches if has_no_barcodes

        return :change_growth_phase if (previous_growth_phase.include?('Veg') && new_growth_phase.include?('Veg')) && moved_to_barcodes

        return :change_growth_phase if (!previous_growth_phase.include?('Flow') && new_growth_phase.include?('Flow')) && moved_to_barcodes

        return :change_plants_growth_phases if (previous_growth_phase.include?('Flow') && new_growth_phase.include?('Flow')) && already_had_barcodes

        return :change_plants_growth_phases if (previous_growth_phase.include?('Veg') && new_growth_phase.include?('Flow')) && already_had_barcodes

        return :move_plants if already_had_barcodes

        DEFAULT_MOVE_STEP
      end
      memoize :next_step

      def move_plants
        completion_barcodes = a_split? ? current_completion.options['barcode'] : barcodes

        payload = completion_barcodes.map do |barcode|
          {
            Id: nil,
            Label: barcode,
            Location: location_name,
            ActualDate: start_time
          }
        end

        call_metrc(:move_plants, payload)
      end

      def move_plant_batches
        payload = {
          Name: batch_tag,
          Location: location_name,
          MoveDate: start_time
        }

        call_metrc(:move_plant_batches, [payload])
      end

      def change_growth_phase
        payload = {
          Name: batch_tag,
          Count: quantity,
          StartingTag: immature?(growth_phase_for_payload) ? nil : first_barcode,
          GrowthPhase: growth_phase_for_payload,
          NewLocation: location_name,
          GrowthDate: start_time,
          PatientLicenseNumber: nil
        }

        call_metrc(:change_growth_phase, [payload])
      end

      def change_plants_growth_phases
        payload = barcodes.map do |barcode|
          {
            Id: nil,
            Label: barcode,
            NewLabel: nil,
            GrowthPhase: growth_phase_for_payload,
            NewLocation: location_name,
            GrowthDate: start_time
          }
        end

        call_metrc(:change_plant_growth_phase, payload)
      end

      def start_time
        @attributes['start_time']
      end

      def immature?(phase = nil)
        phase != 'Flowering'
      end

      # A move that creates a wet weight resource via a generate completion
      # this type of move should not have a transaction of it's own
      # allowing the generate completion to create a wet weight harvest payload using Resource::WetWeight service
      def move_harvest?
        generate_completions.select do |completion|
          completion.parent_id.to_i == current_completion.id &&
            WET_WEIGHT.match?(get_resource_unit(completion.attributes.dig('options', 'resource_unit_id'))&.name)
        end.present?
      end

      def generate_completions
        batch_completions.select do |completion|
          completion.action_type == 'generate'
        end
      end

      def normalized_growth_phase(input = nil)
        return unless input

        case input
        when /veg/i
          'Vegetative'
        when /flow/i
          'Flowering'
        when /cur(e|ing)/i
          'Curing'
        when /dry/i
          'Drying'
        else
          'Clone'
        end
      end

      def quantity
        @attributes.dig('options', 'quantity')&.to_i
      end

      def first_barcode
        return nil if items.blank?

        ordered_items = items.sort_by { |item| item['id'] }
        ordered_items.first['barcode']
      end

      def items_have_barcodes?(tracking_method = nil)
        !tracking_method.nil? && tracking_method != 'none'
      end

      def get_substage(comp = nil)
        comp ||= current_completion
        comp&.included&.dig(:sub_stages)&.first&.name
      end

      def growth_phase_for_completion(comp)
        normalized_growth_phase(get_substage(comp))
      end

      def growth_phase_for_payload
        phase = growth_phase_for_completion(current_completion)
        validate_growth_phase_for_payload!(phase)

        STATE_GROWTH_PHASE_MAP[@integration.state.to_sym][phase.downcase.to_sym]
      end
      memoize :growth_phase_for_payload

      def validate_growth_phase_for_payload!(growth_phase)
        growth_phase_key = growth_phase&.downcase&.to_sym

        case growth_phase_key
        when :vegetative
          true
        when :flowering
          true
        when :drying
          unless move_harvest
            Bugsnag.notify("Missing wet weight output for move completion #{current_completion.id} when moving to Dry") do |notification|
              notification.add_tab(:completion, current_completion)
            end
          end
        else
          Bugsnag.notify("Invalid growth phase #{growth_phase} for move completion #{current_completion.id} in the state of #{@integration.state}") do |notification|
            notification.add_tab(:completion, current_completion)
          end
        end
      end

      def location_name
        current_completion&.included&.dig(:zones)&.first&.name || super
      end

      def a_split?
        current_completion.action_type == 'split'
      end
    end
  end
end
