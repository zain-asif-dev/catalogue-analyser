# frozen_string_literal: true

require 'active_support'
require 'dotenv/load'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# FetchPrepFeeEstimateService
class FetchPrepFeeEstimateService
  include FetchServicesHelperMethods
  def initialize(user, users, list)
    initialize_common(user, users)
    @list = list.map { |entry| entry[:asin] }
    update_user_and_client
    @client = set_client
  end

  def set_client
    MWS.fulfillment_inbound_shipment(
      merchant_id: @user['merchant_id'],
      aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      marketplace: @user['mws_market_place_id'],
      aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      auth_token: @user['auth_token'])
  end

  def parse_data
    response_array = []
    response = @client.get_prep_instructions_for_asin('US', @list).parse
    prep_list = [response['ASINPrepInstructionsList']].flatten

    prep_list.each do |prep_item|
      next if prep_item.blank?

      asins_information = [prep_item['ASINPrepInstructions']].flatten
      asins_information.each do |asin_information|
        instructions = [asin_information['PrepInstructionList']].flatten
        instruction_str ||= ''

        instructions.each do |instruction|
          instruction_str += "#{[instruction['PrepInstruction']].flatten.join(',')}," if instruction.present?
        end

        response_array << { asin: asin_information['ASIN'], prep_instructions: instruction_str.chomp(',') }
      end
    end
    response_array
  end
end
