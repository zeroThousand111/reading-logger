# Reading Logger: A Tool For Logging Pages Read

## Project Description

A basic web app that allows readers to log the number of pages they read at the end of any reading session and get some basic stats about their reading habits.

Its an app written in Ruby using the Sinatra domain-specific language (DSL) to manage the routing and a PostgreSQL database to persist data.

## Features

- Add new readers/delete readers (aka users);
- Log the number of pages read in a reading session;
- Display stats for each user about the number of pages read:
	- Pages read today;
	- Pages read yesterday;
	- Pages read over the past 7 days; and
	- Pages read in total.
- A dashboard that ranks each reader in descending order of pages read over the past 7 days.

## Installation

Clone the repository:

```bash
git clone https://github.com/zeroThousand111/reading-logger
```

Move into the root folder and install dependencies from the `Gemfile` using `bundler`:

```bash
cd reading-logger
bundle install
```

Create a local Postgres database (assuming a PostgreSQL server and `psql` installed on your local machine):

```bash
createdb reading_log
```

Run the application

```bash
ruby reading_logger.rb
```

If you want to use the tests with `minitest` then also create a test database:

```bash
createdb reading_log_test
```

## Demo

A demonstration is currently deployed on Heroku [here](https://gj-reading-logger-app-5154687e3839.herokuapp.com/dashboard).
