# == Class: foreman::config
#
# Fundamental Foreman Configuration items
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
#   Default: '/usr/bin/tfm-ruby'
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
class foreman::config (
  $access_log         = $::foreman::access_log,
  $admin_user         = $::foreman::admin_user,
  $admin_password     = $::foreman::admin_password,
  $error_log          = $::foreman::error_log,
  $host_cert_source   = $::foreman::host_cert_source,
  $log_level          = $::foreman::log_level,
  $passenger_app_root = $::foreman::passenger_app_root,
  $passenger_ruby     = $::foreman::passenger_ruby,
  $puppet_cert_source = $::foreman::puppet_cert_source,
  $server             = $::foreman::server,
  $ssl_dir            = $::foreman::ssl_dir,
  $use_simp_pki       = $::foreman::use_simp_pki,
  $vhost_root         = $::foreman::vhost_root
) inherits ::foreman {

  assert_private()

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

  file { ['/etc/foreman', '/etc/foreman/plugins']:
    ensure  => 'directory',
    owner   => 'root',
    group   => 'foreman',
    mode    => '0750',
    require => Class['::foreman::install']
  }

  if $use_simp_pki {
    include 'pki'

    ::pki::copy { '/etc/foreman':
      group  => 'foreman'
    }

    ::pki::copy { "${::puppet_vardir}/simp":
      group => 'puppet'
    }
  }
  elsif !empty($host_cert_source) {
    file { '/etc/foreman/pki':
      ensure => 'directory',
      owner  => 'root',
      group  => 'puppet',
      mode   => '0640',
      source => $host_cert_source
    }
  }

  # For now, we copy the puppet certs into the foreman space because foreman-proxy
  # seems to have issues running with certs not signed by the Puppet CA. Pending bug
  # fix from Foreman.
  file { $ssl_dir:
    ensure => 'directory',
    owner  => 'root',
    group  => 'foreman',
    mode   => '0750'
  }

  file { "${ssl_dir}/certs":
    ensure  => 'directory',
    owner   => 'root',
    group   => 'foreman',
    mode    => '0775',
    require => File[$ssl_dir]
  }

  file { "${ssl_dir}/private_keys":
    ensure  => 'directory',
    owner   => 'root',
    group   => 'foreman',
    mode    => '0750',
    require => File[$ssl_dir]
  }

  file { "${ssl_dir}/certs/ca.pem":
    owner   => 'root',
    group   => 'foreman',
    mode    => '0664',
    source  => "${puppet_cert_source}/certs/ca.pem",
    require => File[$ssl_dir]
  }

  file { "${ssl_dir}/certs/${::fqdn}.pem":
    owner   => 'root',
    group   => 'foreman',
    mode    => '0660',
    source  => "${puppet_cert_source}/certs/${::fqdn}.pem",
    require => File[$ssl_dir]
  }

  file { "${ssl_dir}/private_keys/${::fqdn}.pem":
    owner   => 'root',
    group   => 'foreman',
    mode    => '0640',
    source  => "${puppet_cert_source}/private_keys/${::fqdn}.pem",
    require => File[$ssl_dir]
  }

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
}