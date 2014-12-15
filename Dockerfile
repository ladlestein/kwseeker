FROM ubuntu:14.10

MAINTAINER Larry Edelstein <ladlestein@gmail.com>

RUN apt-get update -y

RUN apt-get install -y ruby ruby-dev build-essential ca-certificates

RUN useradd -m seeker \
    && echo "seeker:seeker" | chpasswd

RUN gem install bundler

ENV KWSEEKER_GITHUB_AUTH_TOKEN a7338953339f0a8673983eb678acfd2e6700dff2
RUN mkdir -p /var/log/kwseeker \
    && chown seeker:seeker /var/log/kwseeker


USER seeker

WORKDIR /home/seeker

COPY analyze.rb /home/seeker/analyze.rb
COPY job_template.xml /home/seeker/job_template.xml

COPY Gemfile /home/seeker/Gemfile
COPY Gemfile.lock /home/seeker/Gemfile.lock
COPY klocwork_api.rb /home/seeker/klocwork_api.rb

RUN bundle install --path vendor/bundle

CMD ruby ./analyze.rb
