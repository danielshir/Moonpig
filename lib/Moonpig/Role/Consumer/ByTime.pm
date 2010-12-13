package Moonpig::Role::Consumer::ByTime;

use Carp qw(confess croak);
use Moonpig;
use Moonpig::Charge::Basic;
use Moonpig::DateTime;
use Moonpig::Events::Handler::Method;
use Moonpig::Types qw(CostPath);
use Moonpig::Util qw(days event);
use Moose::Role;
use MooseX::Types::Moose qw(ArrayRef Num);
use namespace::autoclean;

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::Consumer',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Behavior::EventHandlers;

use Moonpig::Types qw(Millicents Time TimeInterval);

implicit_event_handlers {
  return {
    heartbeat => {
      low_funds_check => Moonpig::Events::Handler::Method->new(
        method_name => 'check_for_low_funds'),
      charge => Moonpig::Events::Handler::Method->new(
        method_name => 'charge'
       )},
    'low-funds' => {
      low_funds_handler => Moonpig::Events::Handler::Method->new(
        method_name => 'predecessor_running_out',
       )},
    'consumer-create-replacement' => {
      create_replacement => Moonpig::Events::Handler::Method->new(
        method_name => 'create_own_replacement',
       )},
  };
};

after BUILD => sub {
  my ($self) = @_;
  unless ($self->has_last_charge_date) {
    $self->last_charge_date($self->now() - $self->charge_frequency);
  }
};

sub now { Moonpig->env->now() }

# How often I charge the bank
has charge_frequency => (
  is => 'ro',
  default => sub { days(1) },
  isa => TimeInterval,
);

# Description for charge.  You will probably want to override this method
has charge_description => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

# How much I cost to own, in millicents per period
# e.g., a pobox account will have dollars(20) here, and cost_period
# will be one year
has cost_amount => (
  is => 'ro',
  required => 1,
  isa => Millicents,
);

#  XXX this is period in days, which is not quite right, since a
#  charge of $10 per month or $20 per year is not any fixed number of
#  days, For example a charge of $20 annually, charged every day,
#  works out to 5479 mc per day in common years, but 5464 mc per day
#  in leap years.  -- 2010-10-26 mjd

has cost_period => (
   is => 'ro',
   required => 1,
   isa => TimeInterval,
);

# the date is appended to this to make the cost path
# for this consumer's charges
has cost_path_prefix => (
  is => 'ro',
  isa => CostPath,
  required => 1,
);

# When the object has less than this long to live, it will
# start posting low-balance events to its successor, or to itself if
# it has no successor
has old_age => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
);

# Last time I charged the bank
has last_charge_date => (
  is => 'rw',
  isa => Time,
  predicate => 'has_last_charge_date',
);

sub last_charge_exists {
  my ($self) = @_;
  return defined($self->last_charge_date);
}

sub expire_date {
  my ($self) = @_;
  my $bank = $self->bank ||
    confess "Can't calculate remaining life for unfunded consumer";
  my $remaining = $bank->unapplied_amount();
  my $n_full_periods_left = int($remaining/$self->cost_amount); # dimensionless
  return $self->next_charge_date() +
      $n_full_periods_left * $self->cost_period;
}

# returns amount of life remaining, in seconds
sub remaining_life {
  my ($self, $when) = @_;
  $self->expire_date - $when;
}

sub next_charge_date {
  my ($self) = @_;
  return $self->last_charge_date + $self->charge_frequency;
}

# This is the schedule of when to warn the owner that money is running out.
# if the number of days of remaining life is listed on the schedule,
# the object will queue a warning event to the ledger.  By default,
# it does this once per week, and also the day before it dies
has complaint_schedule => (
  is => 'ro',
  isa => ArrayRef [ Num ],
  default => sub { [ 28, 21, 14, 7, 1 ] },
);

has last_complaint_date => (
  is => 'rw',
  isa => 'Num',
  predicate => 'has_complained_before',
);

sub issue_complaint_if_necessary {
  my ($self, $remaining_life) = @_;
  my $remaining_days = $remaining_life / 86_400;
  my $sched = $self->complaint_schedule;
  my $last_complaint_issued = $self->has_complained_before
    ? $self->last_complaint_date
    : $sched->[0] + 1;

  # run through each day since the last time we issued a complaint
  # up until now; if any of those days are complaining days,
  # it is time to issue a new complaint.
  my $complaint_due;
  #  warn ">> <$self> $last_complaint_issued .. $remaining_days\n";
  for my $n ($remaining_days .. $last_complaint_issued - 1) {
    $complaint_due = 1, last
      if $self->is_complaining_day($n);
  }

  if ($complaint_due) {
    $self->issue_complaint($remaining_life);
    $self->last_complaint_date($remaining_days);
  }
}

sub is_complaining_day {
  my ($self, $days) = @_;
  confess "undefined days" unless defined $days;
  for my $d (@{$self->complaint_schedule}) {
    return 1 if $d == $days;
  }
  return;
}

sub issue_complaint {
  my ($self, $how_soon) = @_;
  $self->ledger->handle_event(
    event(
      'contact-humans',
      { why => 'your service will run out soon',
        how_soon => $how_soon,
        how_much => $self->cost_amount,
      }));
}

# XXX this is for testing only; when we figure out replacement semantics
has is_replaceable => (
  is => 'ro',
  isa => 'Bool',
  default => 1,
);

################################################################
#
#

sub charge {
  my ($self, $event, $arg) = @_;

  return unless $self->has_bank;

  my $now = $event->payload->{datetime}
    or confess "event payload has no timestamp";

  while ($self->last_charge_date->precedes($now)) {
    last unless my $charge = $self->make_charge($now);

    $self->current_journal->add_charge_at(
      $charge,
      [@{$self->cost_path_prefix},
       split(/-/, $now->ymd()),
      ]);
    $self->last_charge_date($now);
  }
}

# returns undef if no charge should be made for specified date
sub make_charge {
  my ($self, $when) = @_;
  return if $self->next_charge_date->follows($when);

  return $self->charge_factory->new({
    description => $self->charge_description(),
    amount => $self->cost_per_charge(),
    date => $when,
  });
}

sub charge_factory {
  return "Moonpig::Charge::Basic";
}

sub cost_per_charge {
  my ($self) = @_;

  # Number of cost periods included in each charge
  # (For example, if costs are $10 per 30 days, and we charge daily,
  # there are 1/30 cost periods per day, each costing $10 * 1/30 = $0.33.
  my $n_periods = $self->cost_period / $self->charge_frequency;

  return $self->cost_amount / $n_periods;
}

sub check_for_low_funds {
  my ($self, $event, $arg) = @_;

  return unless $self->has_bank;

  my $tick_time = $event->payload->{datetime}
    or confess "event payload has no timestamp";

  # if this object does not have long to live...
  if ($self->remaining_life($tick_time) <= $self->old_age) {

    # If it has a replacement R, it should advise R that R will need
    # to take over soon
    if ($self->has_replacement) {
      $self->replacement->handle_event(
        event('low-funds',
              { remaining_life => $self->remaining_life($tick_time) }
             ));
    } else {
      # Otherwise it should create a replacement R
      $self->handle_event(
        event('consumer-create-replacement',
              { timestamp => $tick_time,
                mri => $self->replacement_mri,
              })
       );
    }
  }
}

sub create_own_replacement {
  my ($self, $event, $arg) = @_;

  if ($self->is_replaceable && ! $self->has_replacement) {
    my $replacement = $self->replacement_mri
      ->construct({ extra => { self => $self } })
      or return;
    $self->replacement($replacement);
    return $replacement;
  }
  return;
}

sub construct_replacement {
  my ($self, $param) = @_;
  my $repl = $self->new({
    cost_amount     => $self->cost_amount(),
    cost_period     => $self->cost_period(),
    old_age         => $self->old_age(),
    replacement_mri => $self->replacement_mri(),
    ledger          => $self->ledger(),
    %$param,
  });
}

# My predecessor is running out of money
sub predecessor_running_out {
  my ($self, $event, $args) = @_;
  my $remaining_life = $event->payload->{remaining_life}  # In seconds
    or confess("predecessor didn't advise me how long it has to live");
  $self->issue_complaint_if_necessary($remaining_life);
}

1;
