# frozen_string_literal: true

require 'dotenv/load'
# require 'aws-sdk'
require 'json'
require 'peddler'
require_relative '../../modules/fetch_services_helper_methods'

# Fetch and process
class FetchFeeEstimateService
  def initialize(user, users, list)
    @bulk_insertion = Mutex.new
    @user = user
    @users = users
    @list = list
    @client = set_client
  end

  def get_data
    result = []
    response_arr = []
    vendorasins = fetch_vendorasins(@list)
    @list.each_slice(5).each do |list_item|
      retries = 0
      fee_params = []
      list_item.each_with_index do |asin, index|

        vendor_asin = vendorasins.find { |vendor_asin| vendor_asin["asin"] == asin }

        next if vendor_asin.nil?
        fee_param = {
          marketplace_id: ENV['MARKETPLACE_ID'],
          id_type: "ASIN",
          id_value: vendor_asin["asin"],
          identifier: "request#{index}",
          is_amazon_fulfilled: (FetchFeeEstimateService.all_dimensions_present?(vendor_asin) && !(FetchFeeEstimateService.all_dimensions_zero?(vendor_asin))),
          price_to_estimate_fees: {
            listing_price: {
              currency_code: 'USD',
              amount: FetchFeeEstimateService.buyboxprice(vendor_asin)
            },
            shipping: {
              currency_code: 'USD',
              amount: 0
            },
            points: {
              points_number: 0
            }
          }
        }
        fee_params << fee_param
      end

      begin
        response = @client.get_my_fees_estimate(fee_params)
        percentage_remaining = (response.headers["x-mws-quota-remaining"].to_i.to_f / response.headers["x-mws-quota-max"].to_i.to_f * 100).to_i
        update_user_and_client if percentage_remaining <= 25
        result = response.parse
      rescue => e
        retries += 1
        #puts e.message
        if e.message.include?("throttling")
          #puts e.message
          sleep(3)
          retry
        else
          # API call
          update_user_mws_key_valid_status if e.message.include?("denied") || e.message.include?("Missing required parameter")
          update_user_and_client
          retry if retries <=3
        end
      end
    end
    result
    #vendorasin_bulk_update_fees(columns, vendorasins_records)
  end

  def self.vendorasins_records_import(results)
    vendorasin_records = []
    vendorasins = []
    #puts "result_count-------------------------#{results.count}"
    results.each do |result|
      if result['FeesEstimateResultList']['FeesEstimateResult']
        fees_estimates = [result['FeesEstimateResultList']['FeesEstimateResult']].flatten
        vendorasins << vendorasin_records(fees_estimates)
      end
    end
    vendorasins.flatten.each_slice(100).each do |vendorasins_batch|
      vendorasin_records << vendorasin_bulk_import([:asin], vendorasins_batch)
    end
    vendorasin_records
  end

  def self.parse_data(results)
    vendorasins_records = []
    vendorasin_records = vendorasins_records_import(results)
    columns = [:id, :asin, :commissionpct, :commissiionfee, :variableclosingfee]
    results.each do |result|
      if result['FeesEstimateResultList']['FeesEstimateResult']
        fees_estimates = [result['FeesEstimateResultList']['FeesEstimateResult']].flatten
        #vendorasins =  vendorasin_records(fees_estimates)
        #vendorasins = vendorasin_bulk_import([:asin], vendorasins)
        fees_estimates.each do |fee_estimate|
          vendorasin_hash = {id: nil, asin: "", commissionpct: 0, commissiionfee: 0.0, variableclosingfee: 0.0, fba_fee: 0.0}
          if fee_estimate['Status'] == 'Success'
            if fee_estimate['FeesEstimateIdentifier']['IdValue']

              vendor_asin = vendorasin_records.flatten.find{|vendorasin| vendorasin["asin"] == fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s}
              vendorasin_hash[:id] = vendor_asin["id"]
              vendorasin_hash[:asin] = vendor_asin["asin"]

              fee_details = [fee_estimate["FeesEstimate"]["FeeDetailList"]["FeeDetail"]].flatten
              fee_details.each do |fee_detail|
                if fee_detail["FeeType"] == "ReferralFee"
                  commissionpct ||= (fee_detail["FeeAmount"]["Amount"].to_f / buyboxprice(vendor_asin).to_f) * 100 if buyboxprice(vendor_asin).to_f > 0
                  commissiionfee ||= fee_detail["FeeAmount"]["Amount"]
                  vendorasin_hash[:commissionpct] = commissionpct.to_i
                  vendorasin_hash[:commissiionfee] = commissiionfee.to_f
                elsif fee_detail["FeeType"] == "VariableClosingFee"
                  variableclosingfee ||= fee_detail["FeeAmount"]["Amount"]
                  vendorasin_hash[:variableclosingfee] = variableclosingfee.to_f
                elsif fee_detail["FeeType"] == "FBAFees"
                  fba_fee ||= fee_detail["FeeAmount"]["Amount"]
                  vendorasin_hash[:fba_fee] = fba_fee.to_f
                  vendorasin_hash[:fba_fee] = fba_fee_by_item(vendor_asin).to_f if fba_fee.to_f == 0.0
                end
              end
              vendorasins_records.append(vendorasin_hash)
            end
          elsif fee_estimate['Status'] == 'ClientError'
            vendor_asin = vendorasin_records.flatten.find{|vendorasin| vendorasin["asin"] == fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s}
            vendorasin_hash[:id] = vendor_asin["id"]
            vendorasin_hash[:asin] = vendor_asin["asin"]
            if fee_estimate["Error"]["Message"].include?("client-side error")
              vendorasin_hash[:fba_fee] = fba_fee_by_item(vendor_asin).to_f
            end
            vendorasins_records.append(vendorasin_hash)
          end
        end
      end
    end
    vendorasins_records.each_slice(500).each do |vendorasin_bash|
      vendorasin_bulk_update_fees(columns, vendorasin_bash)
    end
  end

  def self.buyboxprice(vendorasin)
    return vendorasin["buyboxprice"] if vendorasin["buyboxprice"].to_f > 0.0
    asin_seller = vendorasin["asin_seller"]
    buy_box_price ||= 0.0
    buy_box_price = asin_seller["listing_price"].to_f + asin_seller["shipping"].to_f if asin_seller.present?
    buy_box_price
  end

  def self.vendorasin_records(fees_estimates)
    vendorasins = []
    fees_estimates.each do |fee_estimate|
      if fee_estimate['Status'] == 'Success'
        if fee_estimate['FeesEstimateIdentifier']['IdValue'].present?
          vendorasins << {asin: fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s}
        end
      elsif fee_estimate['Status'] == 'ClientError'
        vendorasins << {asin: fee_estimate['FeesEstimateIdentifier']['IdValue'].to_s}
      end
    end
    vendorasins
  end

  def self.current_size_tier(vendorasin)
    product_size_tier ||= "N/A"
    return product_size_tier unless all_dimensions_present?(vendorasin)

    sorted_array = [vendorasin["packageheight"].to_f, vendorasin["packagewidth"].to_f, vendorasin["packagelength"].to_f].sort
    shortest_side = sorted_array.min
    longest_side = sorted_array.max
    median_side = sorted_array[1] # Middle value will be median
    girth = (shortest_side + median_side) * 2
    length_plus_girth = longest_side + girth

    if longest_side <= 15 && median_side <=12 && shortest_side <= 0.75 && vendorasin["packageweight"].to_f <= 0.75
      product_size_tier = 'Small Standard Size'
    elsif longest_side <= 18 && median_side <= 14 && shortest_side <= 8 && vendorasin["packageweight"].to_f <= 20
      product_size_tier = 'Large Standard Size'
    elsif longest_side <= 60 && vendorasin["packageweight"].to_f <= 70 && length_plus_girth <= 130 && median_side <=30
      product_size_tier = 'Small Oversize'
    elsif longest_side <= 108 && vendorasin["packageweight"].to_f <= 150
      if (length_plus_girth <= 130)
        product_size_tier = 'Medium Oversize'
      elsif (length_plus_girth <= 165)
        product_size_tier = 'Large Oversize'
      end
    elsif longest_side > 108 && vendorasin["packageweight"].to_f > 150 && length_plus_girth > 165
      product_size_tier = 'Special Oversize'
    end
    product_size_tier
  end

  def self.size_tier_by_item(vendorasin)
    product_size_tier ||= "N/A"
    return product_size_tier unless all_item_dimensions_present?(vendorasin)
    girth = vendorasin["height"].to_f * vendorasin["width"].to_f
    sorted_array = [vendorasin["height"].to_f, vendorasin["width"].to_f, vendorasin["length"].to_f].sort
    shortest_side = sorted_array.min
    longest_side = sorted_array.max
    median_side = sorted_array[1] # Middle value will be median
    length_plus_girth = longest_side + girth

    if longest_side <= 15 && median_side <=12 && shortest_side <= 0.75 && vendorasin["weight"].to_f <= 12
      product_size_tier = 'Small Standard Size'
    elsif longest_side <= 18 && median_side <= 14 && shortest_side <= 8 && vendorasin["weight"].to_f <= 20
      product_size_tier = 'Large Standard Size'
    elsif longest_side <= 60 && vendorasin["weight"].to_f <= 70 && length_plus_girth <= 130
      product_size_tier = 'Small Oversize'
    elsif longest_side <= 108 && vendorasin["weight"].to_f <= 150
      if (length_plus_girth <= 130)
        product_size_tier = 'Medium Oversize'
      elsif (length_plus_girth <= 165)
        product_size_tier = 'Large Oversize'
      end
    elsif longest_side > 108 && vendorasin["weight"].to_f > 150 && length_plus_girth > 165
      product_size_tier = 'Special Oversize'
    end
    product_size_tier
  end

  def self.fba_fee_by_item(vendorasin)
    size_tier = if current_size_tier(vendorasin) != "N/A"
                    current_size_tier(vendorasin)
                elsif size_tier_by_item(vendorasin) != "N/A"
                  size_tier_by_item(vendorasin)
                end
    #puts "size_tier----------------------#{size_tier}"
    return 2.63 if size_tier.nil?
    if size_tier.include?("Small Standard")
      2.50
    elsif size_tier.include?("Large Standard")
      3.48
    elsif size_tier.include?("Small Oversize")
      8.26
    elsif size_tier.include?("Mediumn Oversize")
      11.37
    elsif size_tier.include?("Large Oversize")
      75.78
    elsif size_tier.include?("Special Oversize")
      137.32
    else
      2.63
    end
  end

  def self.all_dimensions_present?(vendorasin)
    (!(vendorasin["packageheight"].blank?) && !(vendorasin["packagewidth"].blank?) && !(vendorasin["packagelength"].blank?) && !(vendorasin["packageweight"].blank?))
  end

  def self.all_item_dimensions_present?(vendorasin)
    (!(vendorasin["height"].blank?) && !(vendorasin["width"].blank?) && !(vendorasin["length"].blank?) && !(vendorasin["weight"].blank?) && !(all_item_dimensions_zero?(vendorasin)))
  end

  def self.all_dimensions_zero?(vendorasin)
    combined_dimensions = [vendorasin["packageheight"].to_f, vendorasin["packagewidth"].to_f, vendorasin["packagelength"].to_f, vendorasin["packageweight"].to_f].uniq
    combined_dimensions.length == 1 && combined_dimensions == [0.0]
  end

  def self.all_item_dimensions_zero?(vendorasin)
    combined_dimensions = [vendorasin["height"].to_f, vendorasin["width"].to_f, vendorasin["length"].to_f, vendorasin["weight"].to_f].uniq
    combined_dimensions.length == 1 && combined_dimensions == [0.0]
  end

  def fetch_vendorasins(vendor_asins)
    request, http = Requests.initialize_request('/vendorasins', 'GET')
    body = {
      "asins": vendor_asins
    }
    request.body = body.to_json
    rescue_exceptions do
      response = http.request(request)
      record = JSON.parse(response.body)
      record["vendorasins"]
    end
  end

  def self.vendorasin_bulk_import(columns, vendor_asins)
    request, http = Requests.initialize_request('/vendorasin_bulk_import_igonre', 'POST')
    body = {
      'columns': columns,
      'records': vendor_asins
    }
    request.body = body.to_json
    begin
      response = http.request(request)
      records = JSON.parse(response.body)
      records["vendorasins"]
    rescue StandardError => e
      #puts "Error: #{e}"
      false
    end
  end

  def self.vendorasin_bulk_update_fees(columns, vendor_asins)
    request, http = Requests.initialize_request('/vendorasin_bulk_update_fees', 'POST')
    body = {
      'columns': columns,
      'records': vendor_asins
    }
    request.body = body.to_json
    begin
      response = http.request(request)
      records = JSON.parse(response.body)
    rescue StandardError => e
      #puts "Error: #{e}"
      false
    end
  end

  def rescue_exceptions
    yield
    rescue StandardError => e
    #puts "Error: #{e}"
    false
  end

  private

  def update_user_and_client
    @user = @users[rand(0..(@users.count-1))]
    @client = set_client
  end
end
