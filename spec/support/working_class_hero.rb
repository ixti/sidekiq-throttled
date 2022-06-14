# frozen_string_literal: true

class WorkingClassHero
  if Sidekiq::VERSION >= "6.3.0"
    include Sidekiq::Job
    include Sidekiq::Throttled::Job
  else
    include Sidekiq::Worker
    include Sidekiq::Throttled::Worker
  end

  sidekiq_options :queue => :heroes

  def perform
    puts <<-TEXT
    As soon as you're born they make you feel small
    By giving you no time instead of it all
    Till the pain is so big you feel nothing at all
    A working class hero is something to be
    A working class hero is something to be

    They hurt you at home and they hit you at school
    They hate you if you're clever and they despise a fool
    Till you're so fucking crazy you can't follow their rules
    A working class hero is something to be
    A working class hero is something to be

    Keep you doped with religion and sex and TV
    And you think you're so clever and classless and free
    But you're still fucking peasants as far as I can see
    A working class hero is something to be
    A working class hero is something to be

    There's room at the top they're telling you still
    But first you must learn how to smile as you kill
    If you want to be like the folks on the hill

    A working class hero is something to be
    A working class hero is something to be
    If you want to be a hero well just follow me
    If you want to be a hero well just follow me
    TEXT
  end
end
