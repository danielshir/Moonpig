package Moonpig::Role::Consumer::ChargesBank;
# ABSTRACT: a consumer that can issue charges
use Moose::Role;
with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Types qw(ChargePath TimeInterval);

use namespace::autoclean;

# the date is appended to this to make the cost path
# for this consumer's charges
has charge_path_prefix => (
  is => 'ro',
  isa => ChargePath,
  coerce => 1,
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

1;