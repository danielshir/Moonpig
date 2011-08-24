package Moonpig::Env::Normal;
# ABSTRACT: a standard, production environment for Moonpig
use Moose;
use MooseX::StrictConstructor;

use Moonpig::DateTime;
use Carp qw(confess);
with 'Moonpig::Role::Env';

use namespace::autoclean;

sub share_roots {}

sub handle_queue_email {
  my ($self, $event, $arg) = @_;

  confess "unimplemented";
}

sub send_email {
  confess "unimplemented";
}

sub storage_class {
  require Moonpig::Storage::Spike;
  'Moonpig::Storage::Spike';
}

sub now {
  return Moonpig::DateTime->now();
}

sub register_object {
  # do nothing
}

1;
