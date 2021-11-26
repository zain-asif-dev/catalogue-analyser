FROM ruby:2.7
RUN mkdir /var/catalog-files
WORKDIR /var/catalog-files
COPY Gemfile /var/catalog-files/Gemfile
COPY Gemfile.lock /var/catalog-files/Gemfile.lock
RUN gem install bundler
RUN bundle install
COPY . /var/catalog-files
CMD ["ruby","read_s3_file.rb"]
