FactoryBot.define do
  factory :integration do
    account

    secret { Faker::Alphanumeric.unique.alphanumeric(number: 10) }
    state { Faker::Address.state_abbr.downcase }
    facility_id { Faker::Number.number(digits: 4) }
    vendor { :metrc }
    license { 'LIC-0001' }
    eod { "#{Time.now.utc.hour}:00" }
    activated_at { Time.now.utc - 10.years }
    timezone { '+00:00' }
    disable_harvest { false }

    factory :integration_with_metrc_creds do
      secret { ENV['METRC_API_SECRET'] }
      state { ENV['METRC_API_STATE'] }
      vendor { :metrc }
      license { ENV['METRC_API_LICENSE'] }
    end

    trait :ncs_vendor do
      state { :ca }
      vendor { :ncs }
      secret { 'ABC1234567890' }
      license { '123456' }
    end

    trait :harvest_sync_disabled do
      disable_harvest { true }
    end
  end
end
