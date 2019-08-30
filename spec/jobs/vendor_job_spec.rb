require 'rails_helper'

RSpec.describe VendorJob, type: :job do
  before :all do
    ActiveJob::Base.queue_adapter = :test
  end

  it 'enqueues a new vendor job' do
    expect { VendorJob.perform_later }.to have_enqueued_job
  end
end
