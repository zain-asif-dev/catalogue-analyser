# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all fetch services
module MWSRequestHelperMethods
  def set_client
    MWS.products(
      merchant_id: @user['merchant_id'],
      aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      marketplace: @user['mws_market_place_id'],
      aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      auth_token: @user['auth_token']
    )
  end

  def check_response(response, response_arr = nil)
    percentage_remaining = (
      response.headers['x-mws-quota-remaining'].to_i.to_f / response.headers['x-mws-quota-max'].to_i * 100
    ).to_i
    update_user_and_client if percentage_remaining <= 25
    return response.parse if response_arr.nil?

    response_arr << response.parse
  end

  private

  def update_user_and_client
    @user = @users[rand(0..(@users.count - 1))]
    @client = set_client
  end
end
