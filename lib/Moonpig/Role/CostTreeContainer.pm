package Moonpig::Role::CostTreeContainer;
use Moose::Role;

use namespace::autoclean;

use Moonpig::CostTree::Basic;

has cost_tree => (
  is   => 'ro',
  does => 'Moonpig::Role::CostTree',
  default  => sub { Moonpig::CostTree::Basic->new },
  handles  => [ qw(add_charge_at total_amount) ],
);

# TODO: make sure that charges added to this receipt have dates that
# precede this date. 2010-10-17 mjd@icgroup.com
has date => (
  is  => 'ro',
  required => 1,
  default => sub { DateTime->now() },
  isa => 'DateTime',
);

1;
