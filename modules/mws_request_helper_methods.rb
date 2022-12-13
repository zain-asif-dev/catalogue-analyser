# frozen_string_literal: true

# Module to define methods to enhance reusability of common methods of all fetch services
module MWSRequestHelperMethods
  def check_response(response, response_arr = nil)
    update_user_and_client
    return response if response_arr.nil?

    response_arr << response
  end

  module Net::HTTPHeader
    def capitalize(name)
      name
    end
    private :capitalize
  end

  # Competitive pricing for asin
  def competitive_pricing_for(list_items)
    endpoint = "#{ENV['SP_API_BASE_URL']}/products/pricing/v0/competitivePrice?MarketplaceId=#{ENV['MARKETPLACE_ID']}&Asins=#{list_items.join('%2C')}&ItemType=Asin"
    sp_api_request(endpoint)
  end

  # Get matching product
  def catalog_matching_product(list_items, page_token = nil)
    endpoint = "#{ENV['SP_API_BASE_URL']}/catalog/2022-04-01/items?identifiersType=#{@list_type}&identifiers=#{list_items.join('%2C')}&marketplaceIds=#{ENV['MARKETPLACE_ID']}&includedData=attributes%2Cdimensions%2CsalesRanks%2Cidentifiers%2Cimages%2CproductTypes&pageSize=20"
    endpoint += "&pageToken=#{page_token}" if page_token.present?
    sp_api_request(endpoint)
  end

  def percent_encode(page_token)
    encoded_token = ''
    page_token.each do |ch|
      ch = "%#{ch.hex}" if ch.match?(/\A[a-zA-Z0-9_.~-]*\z/)
      encoded_token += ch
    end
    encoded_token
  end

  def lowest_price_listing(params)
    endpoint = "#{ENV['SP_API_BASE_URL']}/batches/products/pricing/v0/itemOffers"
    sp_api_post_request(endpoint, params)
  end

  # Fetch the Estimated fee for the items
  def fetch_fee_estimate(params)
    endpoint = "#{ENV['SP_API_BASE_URL']}/products/fees/v0/feesEstimate"
    sp_api_post_request(endpoint, params)
  end

  def sp_api_post_request(endpoint, params)
    access_token = access_token_generation(@user['refresh_token'])
    body = params.to_json
    url = URI(endpoint)
    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true
    signer = get_signature(get_assume_role)
    signature = signer.sign_request(http_method: 'POST', url: url, body: body,
                                    headers: { 'x-amz-access-token' => access_token })
    request = Net::HTTP::Post.new(url)
    request.body = body
    request['Content-Type'] = 'application/json'
    request.add_field 'x-amz-access-token', access_token
    request.add_field 'X-Amz-Date', signature.headers['x-amz-date']
    request.add_field 'X-Amz-Security-Token', signature.headers['x-amz-security-token']
    request.add_field 'x-amz-content-sha256', signature.headers['x-amz-content-sha256']
    request.add_field 'Authorization', signature.headers['authorization']
    response = https.request(request)
    return response if response.code == '200'

    errors = JSON.parse(response.body)['errors']
    if errors.present?
      errors.each do |error|
        next if error['code'].include?('InvalidInput')

        if error['code'].include?('QuotaExceeded') || error['code'].include?('Unauthorized')
          update_user_and_client
          raise 'Auth or throttled'
        end
      end
    end
  end

  def sp_api_request(endpoint, retries = 0)
    access_token = access_token_generation(@user['refresh_token'])
    url = URI(endpoint.to_s)
    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true
    signer = get_signature(get_assume_role)
    signature = signer.sign_request(http_method: 'GET', url: url.to_s,
                                    headers: { 'x-amz-access-token' => access_token })
    request = Net::HTTP::Get.new(url)
    request.add_field 'x-amz-access-token', access_token
    request.add_field 'X-Amz-Date', signature.headers['x-amz-date']
    request.add_field 'X-Amz-Security-Token', signature.headers['x-amz-security-token']
    request.add_field 'x-amz-content-sha256', signature.headers['x-amz-content-sha256']
    request.add_field 'Authorization', signature.headers['authorization']
    response = https.request(request)
    return response if response.code == '200'

    errors = JSON.parse(response.read_body)['errors']
    if errors.present?
      errors.each do |error|
        next if error['code'].include?('InvalidInput')

        if error['code'].include?('QuotaExceeded') && retries < 7
          sleep(1)
          response = sp_api_request(endpoint, retries + 1)
        elsif error['code'].include?('Unauthorized') && retries < 7
          update_user_and_client
          response = sp_api_request(endpoint, retries + 1)
        end
      end
    end
    response
  end

  private

  def update_user_and_client
    @user = @users[rand(0..(@users.count - 1))]
  end

  # Making signature for the all api above to hit SP API
  def get_signature(credentials)
    Aws::Sigv4::Signer.new(
      service: 'execute-api',
      region: 'us-east-1',
      access_key_id: credentials[:access_key_id],
      secret_access_key: credentials[:secret_access_key],
      session_token: credentials[:session_token]
    )
  end

  # will return the access token
  def get_access_token(refresh_token)
    payloads = { grant_type: 'refresh_token', client_id: ENV['CLIENT_ID'],
                 refresh_token: refresh_token, client_secret: ENV['CLIENT_SECRET'] }
    header = { 'Content-Type': 'application/json' }
    response = HTTParty.post(ENV['AUTHENTICATION_URL'], body: payloads.to_json, headers: header)
    response['access_token']
  end

  # Get assume role from the given access token
  def get_assume_role(region = 'us-east-1')
    result = Aws::STS::Client.new(
      region: region,
      credentials: Aws::Credentials.new(
        ENV['SP_ACCESS_KEY_ID'],
        ENV['SP_SECRET_ACCESS_KEY']
      )
    ).assume_role({ role_arn: ENV['ROLE_ARN'], role_session_name: 'sp-api' })
    result[:credentials].to_h
  end

  # Generating the payload for the generating the acess token
  def grantless_access_token_payload
    { client_id: ENV['CLIENT_ID'],
      client_secret: ENV['CLIENT_SECRET'],
      grant_type: 'client_credentials',
      scope: 'sellingpartnerapi::migration' }
  end

  # Payload fot refresh token
  def refresh_token_payload(code)
    { client_id: ENV['CLIENT_ID'],
      client_secret: ENV['CLIENT_SECRET'],
      grant_type: 'authorization_code',
      code: code }
  end

  # Region url
  def url_and_region_maping
    { 'us-east-1': ENV['SP_API_BASE_URL_North_America_REGION'] }
  end

  def grantless_access_token
    payload = grantless_access_token_payload
    headers =  { 'Content-Type' => 'application/json' }
    response = HTTParty.post(ENV['AUTHENTICATION_URL'].to_s, body: payload.to_json, headers: headers)
    response['access_token']
  rescue StandardError => e
    puts e.message
  end

  # Access token generation of for getting the access token
  def access_token_generation(refresh_token)
    if refresh_token.nil?
      grantless_access_token
    else
      get_access_token(refresh_token)
    end
  end
end
