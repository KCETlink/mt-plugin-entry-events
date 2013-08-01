############################################################################
# Copyright © 2010 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# version 2 for more details. You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

package EntryEvent::EntryEvent;
use strict;
use warnings;

use base qw( MT::Object );
use MT::Util qw( epoch2ts );
use EntryEvent::Util qw( ts2datetime );

require DateTime;
require DateTime::Event::ICal;
require DateTime::Set;
require DateTime::Span;

__PACKAGE__->install_properties({
    column_defs => {
        'id' => 'integer not null auto_increment',
        'blog_id' => 'integer not null',
        'entry_id' => 'integer not null',
        'event_date' => 'datetime not null',
        'featured' => 'boolean',
    },
    indexes => {
        entry_id => 1,
        blog_id => 1,
    },
    datasource => 'entryevent',
    primary_key => 'id',
    child_of    => ['MT::Entry', 'MT::Blog'],
    meta => 1,
});

__PACKAGE__->install_meta({
    columns => [ 'ical' ]
});

# format this event's recurrence params in DateTime::Event::ICal format
sub recurrence {
    my $event = shift;
    my $ical = $event->ical;
    # return undef if this has no ical param
    return unless ($ical);

    # convert these time params to datetime objects... unless they already are
    $ical->{dtstart} = ts2datetime($ical->{dtstart}) unless (ref $ical->{dtstart} eq 'DateTime');
    if ($ical->{until}) {
        $ical->{until} = ts2datetime($ical->{until}) unless (ref $ical->{until} eq 'DateTime');
    }
    my $recur = DateTime::Event::ICal->recur(%$ical);
    return $recur;
}

# function to get the next occurence of the given event that occurs after a particular time
sub get_next_occurrence {
    my $event = shift;
    # time is passed in YYYYMMDDHHMMSS format
    my ($time, $recurrence) = @_;

    unless ($time) {
        $time = epoch2ts(undef, time);
    }
    if ($recurrence) {
        return epoch2ts(undef, $recurrence->epoch);
    } else {
        $recurrence = $event->recurrence;
        if ($recurrence) {
            # if this event recurs, let's return the next instance of it after $time
            my $dtime = ts2datetime($time);
            my $next_recurrence = $recurrence->next($dtime);
            return ( $next_recurrence ? (epoch2ts(undef, $next_recurrence->epoch)) : undef );
        } else {
            # this does not recur, so let's just spit out the next date if it's > time
            return ($event->event_date > $time)?$event->event_date:undef;
        }
    }
}

sub parents {
    my $obj = shift;
    {
        blog_id  => MT->model('blog'),
        entry_id => MT->model('entry'),
    };
}

1;
