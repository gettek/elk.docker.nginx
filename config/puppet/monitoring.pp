# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Configures ELK Clustered hosts with Docker
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

  class profiles::monitoring (
    $dockerlvm = true,
    $storage_account,
    $storage_key,
    $elastic_password,
    $elastic_tag,
    $elastic_version,
  ){
  exec { 'set_max_map_count':
    command => 'sysctl -w vm.max_map_count=262144',
    unless  => 'sysctl vm.max_map_count | grep 262144 2>/dev/null',
    path    => ['/usr/bin:/usr/sbin:/bin:/sbin'],
  }

  # Get monitoring repository - branch depends on hostname (development/master)
  ####################################################################################
  $localrepo  = '/media/data/elk.monitoring'
  $remoterepo = 'https://github.com/gettek/elk.docker.nginx.git'
  # determine git branch
  if $::environment == 'production' {
    $gitbranch = 'master'
    $cluster   = '10.243.50.29,10.243.50.28,10.243.50.31'
  }
  else {
    $gitbranch = 'development'
    $cluster   = '172.21.248.133,172.21.248.137,172.21.248.139'
  }
  # create docker environment file
  $nodename = $trusted['hostname']
  $nodeip   = $facts['ipaddress']
  $env_file = "
TAG=${elastic_tag}
ELASTIC_VERSION=${elastic_version}
ELASTIC_HOST_NAME=${nodename}
ELASTIC_HOST_IP=${nodeip}
ELASTIC_CLUSTER=${cluster}
ELASTIC_PASSWORD=${elastic_password}
ELASTIC_CONFIG_DIR=/usr/share/elasticsearch/config
"
  # pull latest repo files
  vcsrepo { $localrepo:
    ensure   => latest,
    provider => git,
    source   => $remoterepo,
    revision => $gitbranch,
    require  => Mount['/media/data'],
  }
  # create datapaths
  file { ["${localrepo}/data", "${localrepo}/data/elasticsearch", "${localrepo}/data/nginx", "${localrepo}/config", "${localrepo}/config/logstash"]:
    ensure       => directory,
    recurse      => true,
    recurselimit => 2,
    mode         => '0777',
    require      => Vcsrepo[$localrepo],
    before       => Exec['docker-compose-up'],
  }
  file { "${localrepo}/.env":
    ensure  => file,
    content => $env_file,
    mode    => '0777',
    require => Vcsrepo[$localrepo],
  }
  file { "${localrepo}/config/logstash/logstash.conf":
    ensure  => file,
    mode    => '0777',
    require => Vcsrepo[$localrepo],
  }

  # Run docker compose against correct clustered host
  #########################################################
  class { '::docker': }
  class {'::docker::compose':
    ensure  => present,
    version => '1.21.2',
    notify  => Exec['docker-compose-up','docker-compose-up-config'],
  }
  exec { 'docker-compose-up':
    cwd     => $localrepo,
    command => 'docker-compose down && docker-compose up -d',
    unless  => 'docker ps -f name=elk_elasticsearch -f status=exited -q 2>/dev/null',
    path    => ['/usr/local/bin:/usr/bin:/usr/sbin:/bin'],
  }
  exec { 'docker-compose-up-config':
    cwd         => $localrepo,
    command     => 'docker-compose down && docker-compose up -d',
    path        => ['/usr/local/bin:/usr/bin:/usr/sbin:/bin'],
    subscribe   => File["${localrepo}/.env","${localrepo}/config/logstash/logstash.conf"],
    refreshonly => true,
  }

  #TODO: Compose does not create containers due to incorrect compose version '3' error, need custom facts below
  ## Issue: https://github.com/puppetlabs/puppetlabs-docker/issues/94

  # docker_compose { "${localrepo}/docker-compose.yml":
  # ensure => present,
  # scale  => {
  # 'elasticsearch' => 1,
  # 'kibana' => 1,
  # 'logstash' => 1,
  # 'nginx' => 1,
  # 'setup_logstash' => 1,
  # 'setup_kibana' => 1,
  # },
  # }

  #TODO:
  ## Convert docker_compose to puppet containers (https://forge.puppet.com/puppetlabs/docker#containers)

  #create custom facts
  # Facter.add(composetag) do
  # setcode "$composetag"
  # end
  # Facter.add(elastic_password) do
  # setcode "$elastic_password"
  # end
  # Facter.add(elastic_cluster) do
  # setcode "$elastic_cluster"
  # end
  # }
  # set environment variables with facter
  # $customfacts.slice(2) |$env_name, $env_value| {
  # exec { "env-${env_name}":
  # before      => Docker_Compose["${elasticnode}/docker-compose.yml"],
  # environment => ["${env_name}=${env_value}"],
  # command     => "echo $env_name > /tmp/${env_value}",
  # #command     => "bash export FACTER_${env_name}=${env_value}; facter", #export is a shell builtin
  # path        => ['/bin:/opt/puppetlabs/bin/'],
  # }
  # }

  # $elastic_host_ip = $facts['networking']['ip']
  # $elastic_host_name = $trusted['hostname']
  # $elastic_cluster = $trusted['hostname'] ? {
  # /^dev/  => "172.21.248.133,172.21.248.137,172.21.248.139",
  # default => "10.243.50.29,10.243.50.28,10.243.50.31",
  # }
  # 
  # docker::run { 'elasticsearch':
  # image            => "docker.elastic.co/elasticsearch/elasticsearch:${composetag}",
  # command          => '/bin/sh -c "while true; do echo hello world; sleep 1; done"',
  # ports            => ['4444', '4555'],
  # expose           => ['4666', '4777'],
  # links            => ['mysql:db'],
  # net              => 'my-user-def-net',
  # volumes          => ['/var/lib/couchdb', '/var/log'],
  # volumes_from     => '6446ea52fbc9',
  # memory_limit     => '10m', # (format: '<number><unit>', where unit = b, k, m or g)
  # cpuset           => ['0', '3'],
  # username         => 'example',
  # hostname         => 'example.com',
  # env_file         => ['/etc/foo', '/etc/bar'],
  # dns              => ['8.8.8.8', '8.8.4.4'],
  # restart_service  => true,
  # privileged       => false,
  # pull_on_start    => false,
  # before_stop      => 'echo "So Long, and Thanks for All the Fish"',
  # before_start     => 'echo "Run this on the host before starting the Docker container"',
  # after            => [ 'container_b', 'mysql' ],
  # depends          => [ 'container_a', 'postgres' ],
  # extra_parameters => [ '--restart=always' ],
  # }

  # mount Azure backups File Store
  if $::environment == 'production' {
    if $trusted['hostname'] =~ '0' {
      file { '/media/data/backups':
        ensure       => directory,
        before       => Mount['/media/data/backups'],
        recurse      => true,
        recurselimit => 2,
        mode         => '0755',
      }
      mount { '/media/data/backups':
        ensure  => 'mounted',
        device  => "//${storage_account}.file.core.windows.net/backups",
        atboot  => true,
        require => File['/media/data/backups'],
        fstype  => 'cifs',
        options => "vers=3.0,username=${storage_account},password=${storage_key},dir_mode=0755,file_mode=0755",
      }
      # Create Cron jobs for daily backup
      cron { 'daily-backups':
        ensure  => present,
        require => Mount['/media/data/backups'],
        command => "/bin/sh  ${localrepo}/script/azurebackup.sh > /dev/null",
        hour    => 0,
        minute  => 30,
        user    => root,
      }
    }
  }
}
