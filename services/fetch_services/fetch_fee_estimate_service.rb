# frozen_string_literal: true

require 'dotenv/load'
# require 'aws-sdk'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# Fetch and process
class FetchFeeEstimateService
  include FetchServicesHelperMethods
  def initialize(user, users, list)
    initialize_common(user, users)
    @list = list
  end

  def fetch_and_process_data
    vendor_asins = []
    data_set = fetch_data_from_mws
    data_set.each do |data|
      vendor_asins << parse_data(data)
    end
    vendor_asins
  end

  def fetch_data_from_mws
    response_arr = []
    retries = 0
    retry_mws_exception(retries) do
      fetch_data(response_arr, generate_fee_params)
    end
    response_arr.flatten
  end

  def fetch_data(response_arr, fee_params)
    response = @client.get_my_fees_estimate(fee_params)
    check_response(response, response_arr)
  end

  def generate_fee_params
    fee_params = []
    @list.each_with_index do |vendor_asin, index|
      next if vendor_asin.nil?

      fee_params << generate_fee_param_hash(vendor_asin, index)
    end
    fee_params
  end

  def generate_fee_param_hash(vendor_asin, index)
    {
      marketplace_id: ENV['MARKETPLACE_ID'],
      id_type: 'ASIN', id_value: vendor_asin[:asin], identifier: "request#{index}",
      is_amazon_fulfilled: (all_dimensions_present?(vendor_asin) && !all_dimensions_zero?(vendor_asin)),
      price_to_estimate_fees: {
        listing_price: { currency_code: 'USD', amount: buyboxprice(vendor_asin) },
        shipping: { currency_code: 'USD', amount: 0 },
        points: { points_number: 0 }
      }
    }
  end

  def fetch_fee_error(vendorasins_records, fee_estimate)
    vendorasins_records << { asin: fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s,
                             status: "error : FetchFeeEstimateService : #{fee_estimate.dig('Error', 'Message')}" }
  end

  def parse_data(fee_estimate_array_hash)
    vendorasins_records = []
    fee_estimate_array = [fee_estimate_array_hash.dig('FeesEstimateResultList', 'FeesEstimateResult')].flatten
    return if fee_estimate_array.nil?

    fee_estimate_array.each do |fee_estimate|
      next if fee_estimate.instance_of?(String)

      if fee_estimate['Error'].present?
        fetch_fee_error(vendorasins_records, fee_estimate)
        next
      end
      vendorasin_hash = generate_vendorasin_hash
      next unless fee_estimate.dig('FeesEstimateIdentifier', 'IdValue')

      vendorasin_hash[:asin] = fee_estimate.dig('FeesEstimateIdentifier', 'IdValue')
      vendor_asin = @list.find { |vendor_asin_hash| vendor_asin_hash[:asin] == vendorasin_hash[:asin] }
      fee_details = [fee_estimate.dig('FeesEstimate', 'FeeDetailList', 'FeeDetail')].flatten
      size_tier = generate_size_tier(vendor_asin)
      vendorasin_hash[:size_tier] = size_tier
      fee_details.each do |fee_detail|
        case fee_detail['FeeType']
        when 'ReferralFee'
          commissionpct ||= (fee_detail.dig('FeeAmount', 'Amount').to_f / buyboxprice(vendor_asin).to_f) * 100 if buyboxprice(vendor_asin).to_f.positive?
          commissiionfee ||= fee_detail.dig('FeeAmount', 'Amount')
          vendorasin_hash[:commissionpct] = commissionpct.to_i
          vendorasin_hash[:commissiionfee] = commissiionfee.to_f
        when 'VariableClosingFee'
          variableclosingfee ||= fee_detail.dig('FeeAmount', 'Amount')
          vendorasin_hash[:variableclosingfee] = variableclosingfee.to_f
        when 'FBAFees'
          fba_fee ||= fee_detail.dig('FeeAmount', 'Amount')
          vendorasin_hash[:fba_fee] = fba_fee.to_f
          vendorasin_hash[:fba_fee] = fba_fee_by_item(size_tier) if fba_fee.to_f.zero?
        end
      end
      vendorasins_records << vendorasin_hash
    end
    vendorasins_records.flatten
  end

  def generate_vendorasin_hash
    {
      asin: '',
      commissionpct: 0,
      commissiionfee: 0.0,
      variableclosingfee: 0.0,
      fba_fee: 0.0,
      size_tier: ''
    }
  end

  def generate_size_tier(vendorasin)
    if all_item_dimensions_present?(vendorasin)
      return product_size_tier(vendorasin[:height].to_f, vendorasin[:width].to_f,
                               vendorasin[:length].to_f, vendorasin[:weight].to_f)
    end

    product_size_tier(
      vendorasin[:packageheight].to_f, vendorasin[:packagewidth].to_f,
      vendorasin[:packagelength].to_f, vendorasin[:packageweight].to_f
    )
  end

  def buyboxprice(vendorasin)
    return vendorasin[:buyboxprice] if vendorasin[:buyboxprice].to_f > 0.0

    asin_seller = vendorasin[:asin_seller]
    buy_box_price ||= 0.0
    buy_box_price = asin_seller[:listing_price].to_f + asin_seller[:shipping].to_f if asin_seller.present?
    buy_box_price
  end

  def vendorasin_records(fees_estimates)
    vendorasins = []
    fees_estimates.each do |fee_estimate|
      case fee_estimate['Status']
      when 'Success'
        if fee_estimate['FeesEstimateIdentifier']['IdValue'].present?
          vendorasins << { asin: fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s }
        end
      when 'ClientError'
        vendorasins << { asin: fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s,
                         status: "error : #{product_data.dig('Error', 'Message')}" }
      end
    end
    vendorasins
  end

  def product_size_tier(length, width, height, weight)
    shortest_side, median_side, longest_side = [length, width, height].sort
    girth = ((shortest_side + median_side) * 2)
    length_plus_girth = longest_side + girth
    if weight <= 0.75 && longest_side <= 15 && median_side <= 12 && shortest_side <= 0.75
      product_size_tier = 'Small Standard Size'
    elsif weight <= 20 && longest_side <= 18 && median_side <= 14 && shortest_side <= 8
      product_size_tier = 'Large Standard Size'
    elsif weight <= 70 && longest_side <= 60 && median_side <= 30 && length_plus_girth <= 130
      product_size_tier = 'Small Oversize'
    elsif weight <= 150 && longest_side <= 108
      if length_plus_girth <= 130
        product_size_tier = 'Medium Oversize'
      elsif length_plus_girth <= 165
        product_size_tier = 'Large Oversize'
      end
    elsif weight > 150 && longest_side > 108 && length_plus_girth > 165
      product_size_tier = 'Special Oversize'
    else
      product_size_tier = 'N/A'
    end
    product_size_tier
  end

  def fba_fee_by_item(size_tier)
    # puts "size_tier----------------------#{size_tier}"
    return 2.63 if size_tier.nil?

    if size_tier.include?('Small Standard')
      2.50
    elsif size_tier.include?('Large Standard')
      3.48
    elsif size_tier.include?('Small Oversize')
      8.26
    elsif size_tier.include?('Mediumn Oversize')
      11.37
    elsif size_tier.include?('Large Oversize')
      75.78
    elsif size_tier.include?('Special Oversize')
      137.32
    else
      2.63
    end
  end

  def all_dimensions_present?(vendorasin)
    (
      !vendorasin[:packageheight].blank? && !vendorasin[:packagewidth].blank? &&
      !vendorasin[:packagelength].blank? && !vendorasin[:packageweight].blank?
    )
  end

  def all_item_dimensions_present?(vendorasin)
    (
      !vendorasin[:height].blank? &&
      !vendorasin[:width].blank? &&
      !vendorasin[:length].blank? &&
      !vendorasin[:weight].blank? &&
      !all_item_dimensions_zero?(vendorasin)
    )
  end

  def all_dimensions_zero?(vendorasin)
    vendorasin[:packageheight].to_f.zero? &&
      vendorasin[:packagewidth].to_f.zero? &&
      vendorasin[:packagelength].to_f.zero? &&
      vendorasin[:packageweight].to_f.zero?
  end

  def all_item_dimensions_zero?(vendorasin)
    vendorasin[:height].to_f.zero? &&
      vendorasin[:width].to_f.zero? &&
      vendorasin[:length].to_f.zero? &&
      vendorasin[:weight].to_f.zero?
  end
end
