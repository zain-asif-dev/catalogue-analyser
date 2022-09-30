# frozen_string_literal: true

require 'dotenv/load'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# FetchCompetitivePricingDataService
class FetchCompetitivePricingDataService
  include FetchServicesHelperMethods
  def initialize(user, users, list)
    initialize_common(user, users)
    @list = list.map { |entry| entry[:asin] }
  end

  def parse_data(competitive_data_set)
    asin_arr = []
    competitive_data_error(competitive_data_set) if competitive_data_set['errors'].present?
    competitive_data_set.dig('payload').each do |competitive_data|
      next if competitive_data.dig('status') == 'ClientError'

      asin = competitive_data['ASIN'].to_s
      product = competitive_data['Product']
      next if product.dig('CompetitivePricing', 'CompetitivePrices').blank?
      asin_arr << vendor_asin_hash(asin, product)
    end
    asin_arr.flatten
  end

  def vendor_asin_hash(asin, product)
    vendor_asin = {}
    competitive_price = product.dig('CompetitivePricing', 'CompetitivePrices')
    is_buybox_fba = (competitive_price.select { |item| item['CompetitivePriceId'] == '1' }).first.present?
    reference_offer = reference_offer(competitive_price, is_buybox_fba)
    reference_offer_type = reference_offer_type(reference_offer)
    vendor_asin.merge!(generate_vendor_asin_hash(asin, reference_offer.dig('Price', 'LandedPrice', 'Amount').to_f,
                                                 "#{reference_offer['condition']} - #{reference_offer_type}",
                                                 is_buybox_fba))
    update_buybox_price(competitive_price, vendor_asin)
    vendor_asin
  end

  def update_buybox_price(competitive_price, vendor_asin)
    competitive_price.each do |item|
      if item['condition'].to_s == 'New' && item['CompetitivePriceId'] == '1'
        price = item.dig('Price', 'LandedPrice', 'Amount').to_f || 999_999
        vendor_asin[:buyboxprice] = price
      end
    end
  end

  def reference_offer(competitive_price, is_buybox_fba)
    return competitive_price.select { |item| item['CompetitivePriceId'] == '1' }.first if is_buybox_fba

    competitive_price.min_by { |elem| elem.dig('Price', 'ListingPrice', 'Amount').to_f }
  end

  def reference_offer_type(reference_offer)
    return 'Buy Box' if reference_offer['CompetitivePriceId'] == '1'

    'Lowest FBA'
  end

  def generate_vendor_asin_hash(asin, reference_offer_price, reference_offer_type, is_buybox_fba)
    {
      asin: asin,
      referenceoffertype: reference_offer_type,
      referenceoffer: reference_offer_price,
      reference_offer_type: reference_offer_type,
      reference_offer: reference_offer_price,
      isbuyboxfba: is_buybox_fba,
      buyboxprice: 0.0
    }
  end

  def competitive_data_error(competitive_data_set)
    entry = @entries.find { |item| item[:asin] == competitive_data_set['ASIN'] }
    entry[:status] = "code: #{competitive_data_set.dig('errors', 0, 'code')}, error : FetchCompetitivePricingDataService : #{competitive_data_set.dig('errors', 0, 'message')}"
  end

  def fetch_data(response_arr, list_item)
    response = JSON.parse(competitive_pricing_for(list_item).read_body)
    # @client.get_competitive_pricing_for_asin(ENV['MARKETPLACE_ID'], list_item)
    check_response(response, response_arr)
  end
end
