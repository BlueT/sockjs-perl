package SockJS::Transport::XHRStreaming;

use strict;
use warnings;

use SockJS::Exception;

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    return $self;
}

sub dispatch {
    my $self = shift;
    my ($env, $session, $path) = @_;

    if ($env->{REQUEST_METHOD} eq 'OPTIONS') {
        my $origin       = $env->{HTTP_ORIGIN};
        my @cors_headers = (
            'Access-Control-Allow-Origin' => !$origin
              || $origin eq 'null' ? '*' : $origin,
            'Access-Control-Allow-Credentials' => 'true'
        );

        return [
            204,
            [   'Expires'                      => '31536000',
                'Cache-Control'                => 'public;max-age=31536000',
                'Access-Control-Allow-Methods' => 'OPTIONS, POST',
                'Access-Control-Max-Age'       => '31536000',
                @cors_headers
            ],
            ['']
        ];
    }

    return [400, ['Content-Length' => 11], ['Bad request']]
      unless $env->{REQUEST_METHOD} eq 'POST';

    if ($session->is_connected && !$session->is_reconnecting) {
        return [
            200,
            ['Content-Length' => 40],
            [qq{c[2010,"Another connection still open"]\n}]
        ];
    }

    my $limit = 4096;

    return sub {
        my $respond = shift;

        my $chunked = $env->{SERVER_PROTOCOL} eq 'HTTP/1.1';

        my $writer = $respond->(
            [   200,
                [   'Content-Type' => 'application/javascript; charset=UTF-8',
                    'Access-Control-Allow-Origin'      => '*',
                    'Access-Control-Allow-Credentials' => 'true',
                    $chunked
                    ? ('Transfer-Encoding' => 'chunked')
                    : ()
                ]
            ]
        );

        $session->on(
            write => sub {
                my $session = shift;

                my $message = 'a' . JSON::encode_json([@_]);

                $writer->write(
                    $self->_build_chunk($chunked, $message . "\n"));

                $limit -= length($message) - 1;

                if ($limit <= 0) {
                    $session->on(write => undef);
                    $session->reconnecting;

                    $writer->write($self->_build_chunk($chunked, ''));
                    $writer->close;
                }
            }
        );

        $session->on(
            close => sub {
                my $session = shift;
                my ($code, $message) = @_;

                $code = int $code;

                $writer->write(
                    $self->_build_chunk(
                        $chunked, qq{c[$code,"$message"]} . "\n"
                    )
                );
                $writer->write($self->_build_chunk($chunked, ''));
                $writer->close;
            }
        );

        $writer->write($self->_build_chunk($chunked, ('h' x 2048) . "\n"));
        $limit -= 4;
        $writer->write($self->_build_chunk($chunked, 'o' . "\n"));

        if ($session->is_connected) {
            $session->reconnected;
        }
        else {
            $session->connected;
        }
    };
}

sub _build_chunk {
    my $self = shift;
    my ($chunked, $chunk) = @_;

    return $chunk unless $chunked;

    return
        (unpack 'H*', pack 'N*', length($chunk))
      . "\x0d\x0a"
      . $chunk
      . "\x0d\x0a";
}

1;
