package SockJS::Transport::EventSource;

use strict;
use warnings;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    $self->{response_limit} ||= 128 * 1024;

    return $self;
}

sub dispatch {
    my $self = shift;
    my ($env, $session, $path) = @_;

    my $limit = $self->{response_limit};

    return sub {
        my $respond = shift;

        my $writer = $respond->(
            [   200,
                [   'Content-Type' => 'text/event-stream; charset=UTF-8',
                    'Connection'   => 'close',
                    'Cache-Control' =>
                      'no-store, no-cache, must-revalidate, max-age=0'
                ]
            ]
        );

        if ($session->is_connected && !$session->is_reconnecting) {
            $writer->write("\x0d\x0a");
            $writer->write(qq{data: c[2010,"Another connection still open"]\x0d\x0a\x0d\x0a\n"});
            $writer->close;
            return;
        }

        $session->on(
            syswrite => sub {
                my $session = shift;
                my ($message) = @_;

                $limit -= length($message) - 1;

                $writer->write("data: $message\x0d\x0a\x0d\x0a");

                if ($limit <= 0) {
                    $writer->close;

                    $session->reconnecting;
                }
            }
        );

        $session->on(close => sub { $writer->close });

        $writer->write("\x0d\x0a");
        $session->syswrite('o');

        if ($session->is_closed) {
            $session->close;
        }
        else {
            if ($session->is_connected) {
                $session->reconnected;
            }
            else {
                $session->connected;
            }
        }
    };
}

1;
