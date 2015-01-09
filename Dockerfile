FROM ubuntu:14.10

MAINTAINER Larry Edelstein <ladlestein@gmail.com>

RUN apt-get update -y

RUN apt-get install -y ruby ruby-dev build-essential ca-certificates

RUN useradd -m seeker \
    && echo "seeker:seeker" | chpasswd

RUN gem install bundler

WORKDIR /home/seeker

COPY Gemfile /home/seeker/Gemfile
COPY Gemfile.lock /home/seeker/Gemfile.lock

USER seeker

RUN bundle install --path vendor/bundle

ENV KWSEEKER_GITHUB_AUTH_TOKEN a7338953339f0a8673983eb678acfd2e6700dff2

COPY analyze.rb /home/seeker/analyze.rb
COPY job_template.xml /home/seeker/job_template.xml

COPY klocwork_api.rb /home/seeker/klocwork_api.rb

USER root

RUN chown -R seeker:seeker .

USER seeker

CMD ruby ./analyze.rb
