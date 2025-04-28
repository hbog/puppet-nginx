# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'nginx::resource::mailhost define:' do
  has_recent_mail_module = true

  has_recent_mail_module = false if fact('os.family') == 'RedHat' && fact('os.release.major') == '8'

  it 'remove leftovers from previous tests', if: fact('os.family') == 'RedHat' do
    # nginx-mod-mail is not available for all versions of nginx, the one
    # installed might be incompatible with the version of nginx-mod-mail we are
    # about to install so clean everything.
    pp = "
    yumrepo { 'nginx-release':
      ensure => absent,
    }
    yumrepo { 'passenger':
      ensure => absent,
    }
    "
    apply_manifest(pp, catch_failures: true)
    shell('yum -y remove nginx nginx-filesystem passenger nginx-mod-mail')
    shell('yum clean all')
  end

  context 'actualy test the mail module', if: has_recent_mail_module do
    it 'runs successfully' do
      pp = "
      class { 'nginx':
        mail            => true,
      }
      nginx::resource::mailhost { 'domain1.example':
        ensure      => present,
        auth_http   => 'localhost/cgi-bin/auth',
        protocol    => 'smtp',
        listen_port => 587,
        ssl         => true,
        ssl_port    => 465,
        ssl_cert    => '/etc/pki/tls/certs/blah.cert',
        ssl_key     => '/etc/pki/tls/private/blah.key',
        xclient     => 'off',
        proxy_protocol  => 'off',
        proxy_smtp_auth => 'off',
      }
      "

      apply_manifest(pp, catch_failures: true)
      # The module produce different config when nginx is installed and when it
      # is not installed prior to getting facts, so we need to re-apply the
      # catalog.
      apply_manifest(pp, catch_failures: true)
    end

    describe file('/etc/nginx/conf.mail.d/domain1.example.conf') do
      it { is_expected.to be_file }
      it { is_expected.to contain 'auth_http             localhost/cgi-bin/auth;' }
      it { is_expected.to contain 'listen                *:465 ssl;' }
    end

    describe port(587) do
      it { is_expected.to be_listening }
    end

    describe port(465) do
      it { is_expected.to be_listening }
    end

    context 'when configured for nginx 1.14', if: !%w[Debian Archlinux].include?(fact('os.family')) do
      shell('yum -y install nginx-1.14.1') if fact('os.family') == 'RedHat' && fact('os.release.major') == '8'
      it 'runs successfully' do
        pp = "
      class { 'nginx':
        mail            => true,
        manage_repo     => false,
        nginx_version   => '1.14.0',
      }
      nginx::resource::mailhost { 'domain1.example':
        ensure      => present,
        auth_http   => 'localhost/cgi-bin/auth',
        protocol    => 'smtp',
        listen_port => 587,
        ssl         => true,
        ssl_port    => 465,
        ssl_cert    => '/etc/pki/tls/certs/blah.cert',
        ssl_key     => '/etc/pki/tls/private/blah.key',
        xclient     => 'off',
      }
        "

        apply_manifest(pp, catch_failures: true)
      end

      describe file('/etc/nginx/conf.mail.d/domain1.example.conf') do
        it 'does\'t contain `ssl` on `listen` line' do
          is_expected.to contain 'listen                *:465;'
        end
      end
    end
  end
end
