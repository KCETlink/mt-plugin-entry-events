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

package EntryEvent::CMS;

use strict;
use warnings;

use MT;
use MT::Util qw( format_ts );
require EntryEvent::EntryEvent;

sub source_edit_entry {
    my ($cb, $app, $tmpl) = @_;
    my $plugin = MT->component('entryevents');
    my $blog_id = $app->param('blog_id');
    if ($plugin->get_config_value('show_events', 'blog:'.$blog_id)) {
        my $old = q{<div id="feedback-field"};
        my $new_tmpl = $plugin->load_tmpl('events-widget.tmpl');
        my $new = $new_tmpl->text;
        $$tmpl =~ s/\Q$old\E/$new$old/;
    }

}

sub param_edit_entry {
    my ($cb, $app, $param, $tmpl) = @_;
    my $entry_id = $app->param('id');
    if ($entry_id) {
        my $event = EntryEvent::EntryEvent->load({ entry_id => $entry_id });
        if ($event) {
            $param->{featured} = $event->featured;

            my $event_date = $event->event_date;
            my $ical = $event->ical;
            if ($ical) {
                $param->{has_recurrence} = 1;
                if ($ical->{interval} || $ical->{byday}) { # this is a custom frequency
                    $param->{frequency} = 'custom';
                    $param->{custom_frequency} = $ical->{freq};
                    if ($ical->{freq} eq 'monthly' && $ical->{byday} =~ m/(-?\d)(.+)/) {
                        $param->{monthly_interval} = $1;
                        $param->{monthly_day} = $2;
                    } elsif ($ical->{freq} eq 'weekly') {
                        $param->{weekly_interval} = $ical->{interval};
                        for my $day (@{$ical->{byday}}) {
                            $param->{"weekly_day_$day"} = 1;
                        }
                    } else { # set it to either daily_interval or yearly_interval
                        $param->{$ical->{freq} . 'interval'} = $ical->{interval};
                    }
                } else {
                    $param->{frequency} = $ical->{freq};
                }
                $param->{dtstart} = $ical->{dtstart};
                $param->{until} = format_ts('%m/%d/%Y', $ical->{until});
            }
            my $date = format_ts('%m/%d/%Y' , $event_date);
            my $hour = format_ts('%l', $event_date);
            my $minute = format_ts('%M', $event_date);

            $param->{event_date} = $date;
            $param->{event_minute} = $minute;
            $param->{event_hour} = $hour;
            $param->{event_ampm} = lc(format_ts('%p', $event_date));
        }

    }
}

sub post_save_entry {
    my ($cb, $app, $entry) = @_;
    my $plugin = MT->component('entryevents');
    return 1 unless ($plugin->get_config_value('show_events', 'blog:'.$entry->blog_id)); # only do this if this is an events blog
    return 1 unless ($app->param('has_date'));

    my $hour = $app->param('event-hour');
    my $minute = $app->param('event-minute');
    my $ampm = $app->param('ampm');

    my $date = $app->param('event-date');
    my $has_recurrence = $app->param('has_recurrence');
    my $featured = $app->param('featured');

    my ($month, $day, $year) = split('/', $date);

    # we need to do some validation here
    if ($month < 1 || $month > 12) {
        return $app->error("The 'month' parameter for an Event date must be between 1 and 12.");
    }

    if ($day < 1 || $day > 31) {
        return $app->error("The 'day' parameter for an Event date must be between 1 and 31.");
    }

    if ($year < 0) {
        return $app->error("The 'year' parameter for an Event date must be greater than 0.")
    }

    if ($hour < 1 || $hour > 12) {
        return $app->error("The 'hour' parameter for an Event must be between 1 and 12.");
    }

    if ($minute < 0 || $minute > 60) {
        return $app->error("The 'minute' parameter for an Event must be between 0 and 60.");
    }



    if ($ampm eq 'pm' && $hour < 12) {
        $hour += 12;
    } elsif ($ampm eq 'am' && $hour == 12) {
        $hour = '00';
    }

    # zero-pad things
    if ($hour < 10) {
        $hour = "0" . $hour;
    }

    if ($minute < 10) {
        $minute = "0" . $minute;
    }

    my $ts = join('', $year, $month, $day, $hour, $minute, '00');

    my $saved_time = EntryEvent::EntryEvent->load({ entry_id => $entry->id });
    if ($saved_time) { # update the existing time if it's there
        $saved_time->event_date($ts);
        $saved_time->featured($featured);
        if ($has_recurrence) {
            $saved_time->ical(get_ical_params($app, $entry, $ts));
        } else {
            $saved_time->ical(undef); # blank this out if it's not set
        }
        $saved_time->save;
    } else { # create a new entry
        $saved_time = EntryEvent::EntryEvent->new;
        $saved_time->entry_id($entry->id);
        $saved_time->blog_id($entry->blog_id);
        $saved_time->event_date($ts);
        $saved_time->featured($featured);

        if ($has_recurrence) {
            $saved_time->ical(get_ical_params($app, $entry, $ts));
        }
        $saved_time->save;
    }

}

sub get_ical_params {
    my $app = shift;
    my ($entry, $ts) = @_;
    my %params;

    my $end_recurrence = $app->param('recurrence_end');
    $end_recurrence .= ' 23:59:59';  # set the end time to be the end of this day

    require Date::Parse;
    my @end_recur = Date::Parse::strptime($end_recurrence);

    if (!@end_recur) {
        my $class_label = $entry->class_label;
        my $entry_title = $entry->title;
        my $entry_id    = $entry->id;

        my $message = "EntryEvents: $class_label '$entry_title' (ID:$entry_id): ";
        $message   .= "Invalid or unrecognized date in 'Until' parameter.";

        require MT::Log;
        $app->log(
            {
                message => $message,
                class => system,
                level => MT::Log::ERROR(),
                category => 'callback',
            }
        );

        return undef;
    }

    $end_recurrence = sprintf '%04d%02d%02d%02d%02d%02d',
        $end_recur[5] + 1900, $end_recur[4] + 1, @end_recur[ 3, 2, 1, 0 ];

    $params{dtstart} = $ts;
    $params{until} = $end_recurrence;

    my $interval = $app->param('interval');
    if ($interval) {
        if ($interval eq 'custom') {
            # we have a custom interval, whee
            # need to handle these individually
            my $custom_freq = $app->param('custom-frequency');
            $params{freq} = $custom_freq;
            if ($custom_freq eq 'daily') {
                # we can have a daily interval for events like "this occurs every X days"
                $params{interval} = $app->param('daily-interval');
            } elsif ($custom_freq eq 'weekly') {
                # we can have a weekly interval for events like "this occurs every X weeks on Y day"
                $params{interval} = $app->param('weekly-interval');
                $params{byday} = [ $app->param('weekly-day') ];
            } elsif ($custom_freq eq 'monthly') {
                # we can have a monthly interval for events like "this occurs on the Xth specific day of every month" (the 4th Friday, eg)
                $params{byday} = $app->param('monthly-interval') . $app->param('monthly-day');
            } elsif ($custom_freq eq 'yearly') {
                # we can have a yearly interval for events, like "this occurs on this date every 17 years" (track cicada activity, yay!)
                $params{interval} = $app->param('yearly-interval');
            }
        } else {
            # just set the frequency, it's a simple weekly/monthly/etc.
            $params{freq} = $interval;
        }
    }
    return \%params;
}

1;
