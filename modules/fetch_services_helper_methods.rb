# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all fetch services
module FetchServicesHelperMethods
  def initialize_common(user, users)
    @user = user
    @users = users
    @client = set_client
  end

  def set_client
    MWS.products(
      merchant_id: @user['merchant_id'],
      aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      marketplace: @user['mws_market_place_id'],
      aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      auth_token: @user['auth_token']
    )
  end

  def fetch_and_process_data(slice_size)
    vendor_asins = []
    data_set = fetch_data_from_mws(slice_size)
    data_set.each do |data|
      vendor_asins << parse_data(data)
    end
    vendor_asins
  end

  def fetch_data_from_mws(slice_size)
    response_arr = []
    retries = 0
    @list.each_slice(slice_size).each do |list_item|
      retries = 0
      retry_mws_exception(retries) do
        fetch_data(response_arr, list_item)
      end
    end
    response_arr.flatten
  end

  def check_response(response, response_arr)
    percentage_remaining = (
      response.headers['x-mws-quota-remaining'].to_i.to_f / response.headers['x-mws-quota-max'].to_i * 100
    ).to_i
    update_user_and_client if percentage_remaining <= 25
    response_arr << response.parse
  end

  def retry_mws_exception(retries)
    yield
  rescue StandardError => e
    retries += 1
    puts e.message
    update_user_and_client
    if e.message.include?('throttled')
      retry
    elsif retries <= 3
      # update_user_mws_key_valid_status if e.message.include?('denied') ||
      # e.message.include?('Missing required parameter');
      retry
    end
  end

  private

  def update_user_and_client
    @user = @users[rand(0..(@users.count - 1))]
    @client = set_client
  end
end
