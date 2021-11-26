# frozen_string_literal: true

require_relative 'mws_request_helper_methods'
# Module to define methods to enhance reusability of common methods of all fetch services
module FetchServicesHelperMethods
  include MWSRequestHelperMethods
  def initialize_common(user, users)
    @user = user
    @users = users
    @client = set_client
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

  def retry_mws_exception(retries)
    yield
  rescue StandardError => e
    retries += 1
    puts e.message
    if e.message.include?('throttled') || e.message.include?('throttling')
      update_user_and_client
      retry
    elsif e.message.include?('Auth')
      update_user_and_client
      retry
    elsif retries <= 3
      update_user_and_client
      # update_user_mws_key_valid_status if e.message.include?('denied') ||
      # e.message.include?('Missing required parameter');
      retry
    end
  end
end
