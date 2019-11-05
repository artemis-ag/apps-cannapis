class Account < ApplicationRecord
  attr_reader :_client

  has_many :integrations
  has_many :transactions

  def refresh_token_if_needed
    return unless @_client.oauth_token.expired?

    new_token = @_client.refresh
    expires_in = (new_token.to_hash[:expires_at].to_i - new_token.to_hash[:created_at].to_i)
    update(access_token: new_token.to_hash[:access_token],
           refresh_token: new_token.to_hash[:refresh_token],
           access_token_expires_in: expires_in,
           access_token_created_at: Time.zone.now)
  end

  def client
    @_client ||= ArtemisApi::Client.new(access_token: access_token,
                                        refresh_token: refresh_token,
                                        expires_at: access_token_expires_in)
  end
end
