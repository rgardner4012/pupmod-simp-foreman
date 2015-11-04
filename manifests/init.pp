# == Class: foreman
#
# A SIMP based setup of the Foreman. SIMP strips out all non-essential
# features of the Foreman and provides a basic web interface for Puppet
# reporting and information.
#
# == Parameters
#
# [*access_log*]
#   Type: Absolute Path/String
#   Default: '/var/log/httpd/foreman_access.log'
#
#   The httpd access log for the Foreman web UI.
#
# [*admin_pass*]
#   Type: String
#   Default: Randomly generated by passgen
#
#   The password for the admin user, used to log into the Foreman web
#   UI.
#
# [*error_log*]
#   Type: Absolute Path/String
#   Default: '/var/log/httpd/foreman_error.log'
#
#   The error log for the Foreman web UI.
#
# [*host_cert_source*]
#   Type: Absolute Path/String
#   Default: ''
#
#   Specifies where the host PKI keys are kept. If use_simp_pki is set
#   to false, then the hosts keys will be copied from here into the
#   foreman space.
#
# [*passenger_app_root*]
#   Type: Absolute Path/String
#   Default: '/usr/share/foreman'
#
#   The directory which Passenger will run inside of.
#
# [*passenger_ruby*]
#   Type: Executable/String
#   Default: '/usr/bin/ruby193-ruby'
#
#   The ruby executable that Passenger will use.
#
# [*server*]
#   Type: Hostname/String
#   Default: <fqdn_puppetmasteer>
#
#   The server that the Foreman will run on.
#
# [*use_simp_pki*]
#   Type: Boolean
#   Default: True
#
#   Whether or not to copy PKI certs into the foreman space using the
#   SIMP pki::copy tool.
#
# [*use_ssl*]
#   Type: Boolean
#   Default: True
#
#   Whether or not to include an SSL conf for the Foreman web UI.
#
# [*vhost_root*]
#   Type: Absolute Path/String
#   Default: '/usr/share/foreman/public'
#
#   The root of the Foreman web interface.
#
# == Variables
#
# [*fqdn*]
#   Used to set the VirtualHost ServerName variable in the Apache conf file.
#
# == Authors
#
# Kendall Moore <kmoore@keywcorp.com>
#
class foreman (
  $access_log         = '/var/log/httpd/foreman_access.log',
  $admin_user         = hiera('foreman::admin_user', $::foreman::params::admin_user),
  $admin_password     = hiera('foreman::admin_password', $::foreman::params::admin_password),
  $error_log          = '/var/log/httpd/foreman_error.log',
  $host_cert_source   = '',
  $log_level          = hiera('foreman::log_level', $::foreman::params::log_level),
  $passenger_app_root = '/usr/share/foreman',
  $passenger_ruby     = '/usr/bin/ruby193-ruby',
  $puppet_cert_source = "${::puppet_vardir}/ssl",
  $server             = $::foreman::params::server,
  $ssl_dir            = '/etc/foreman/ssl',
  $use_simp_pki       = true,
  $use_ssl            = true,
  $vhost_root         = '/usr/share/foreman/public'
) inherits foreman::params {

  validate_absolute_path($access_log)
  validate_absolute_path($error_log)
  validate_absolute_path($passenger_app_root)
  validate_absolute_path($passenger_ruby)
  validate_absolute_path($vhost_root)
  validate_bool($use_ssl)
  validate_net_list($server)

  package { 'foreman':                     ensure => 'latest' }
  package { 'foreman-release':             ensure => 'latest' }
  package { 'foreman-cli':                 ensure => 'latest' }
  package { 'foreman-selinux':             ensure => 'latest' }
  package { 'ruby193-rubygem-rest-client':
    ensure => 'latest',
    before => Foreman::User['admin']
  }

  pupmod::conf { 'foreman-reports':
    setting => 'reports',
    value   => 'log, foreman'
  }

  if $::selinux_current_mode and $::selinux_current_mode != 'disabled' {
    selboolean { [
      'httpd_run_foreman',
      'passenger_run_foreman',
      'puppetmaster_use_db'
    ]:
      persistent => true,
      value      => 'on'
    }
  }

  pam::access::manage { 'foreman':
    users   => 'foreman',
    origins => ['ALL']
  }

  include '::foreman::database'

  file { ['/etc/foreman', '/etc/foreman/plugins']:
    ensure  => 'directory',
    owner   => 'root',
    group   => 'foreman',
    mode    => '0750',
    require => Package['foreman'],
    notify  => Service['foreman']
  }

  include '::foreman::settings'

  if $use_simp_pki {
    include 'pki'

    ::pki::copy { '/etc/foreman':
      group  => 'foreman',
      notify => Service['foreman']
    }

    ::pki::copy { "$::puppet_vardir/simp":
      group => 'puppet'
    }
  }
  elsif !empty($host_cert_source) {
    file { '/etc/foreman/pki':
      ensure => 'directory',
      owner  => 'root',
      group  => 'puppet',
      mode   => '0640',
      source => $host_cert_source,
      notify => Service['foreman']
    }
  }

  # For now, we copy the puppet certs into the foreman space because foreman-proxy
  # seems to have issues running with certs not signed by the Puppet CA. Pending bug
  # fix from Foreman.
  file { $ssl_dir:
    ensure => 'directory',
    owner  => 'root',
    group  => 'foreman',
    mode   => '0750',
    notify => Service['foreman']
  }

  file { "${ssl_dir}/certs":
    ensure  => 'directory',
    owner   => 'root',
    group   => 'foreman',
    mode    => '0775',
    require => File[$ssl_dir],
    notify  => Service['foreman']
  }

  file { "${ssl_dir}/private_keys":
    ensure  => 'directory',
    owner   => 'root',
    group   => 'foreman',
    mode    => '0750',
    require => File[$ssl_dir],
    notify  => Service['foreman']
  }

  file { "${ssl_dir}/certs/ca.pem":
    owner   => 'root',
    group   => 'foreman',
    mode    => '0664',
    source  => "${puppet_cert_source}/certs/ca.pem",
    require => File[$ssl_dir],
    notify  => Service['foreman']
  }

  file { "${ssl_dir}/certs/${::fqdn}.pem":
    owner   => 'root',
    group   => 'foreman',
    mode    => '0660',
    source  => "${puppet_cert_source}/certs/${::fqdn}.pem",
    require => File[$ssl_dir],
    notify  => Service['foreman']
  }

  file { "${ssl_dir}/private_keys/${::fqdn}.pem":
    owner   => 'root',
    group   => 'foreman',
    mode    => '0640',
    source  => "${puppet_cert_source}/private_keys/${::fqdn}.pem",
    require => File[$ssl_dir],
    notify  => Service['foreman']
  }

  include '::foreman::passenger'

  file { "${::puppet_ruby_dir}/reports/foreman.rb":
    ensure => 'present',
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => 'puppet:///modules/foreman/foreman.rb'
  }

  file { '/etc/puppet/foreman.yaml':
    ensure  => 'present',
    owner   => 'root',
    group   => 'puppet',
    mode    => '0640',
    content => template('foreman/etc/puppet/foreman.yaml.erb')
  }

  include '::apache::conf'

  apache::add_site { '05-foreman':
    content => template('foreman/etc/httpd/conf.d/05-foreman.conf.erb')
  }

  file { '/etc/httpd/conf.d/05-foreman.d':
    ensure  => 'directory',
    owner   => 'root',
    group   => 'apache',
    mode    => '0750',
    require => Package['httpd']
  }

  include '::foreman::proxy'

  if $use_ssl { include '::foreman::ssl' }

  service { 'foreman':
    ensure  => 'running',
    enable  => true,
    require => Package['foreman'],
    notify  => Service['httpd']
  }

  foreman::user { 'admin':
    auth_source => 'Internal',
    password    => $admin_password,
    api_admin   => true,
    web_admin   => true,
    email       => "root@${::domain}",
    firstname   => 'Admin',
    lastname    => 'User'
  }

  Foreman::User <| title == 'admin' |> -> Foreman::User <| title != 'admin' |>
  Foreman::User <| title == 'admin' |> -> Foreman::Smart_proxy <| |>
  Foreman::User <| title == 'admin' |> -> Foreman::Auth_source <| |>
}