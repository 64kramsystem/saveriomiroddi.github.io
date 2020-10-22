---
layout: post
title: Monitoring the CPU steal time on AWS EC2 instances
tags: [aws,cloud,linux,monitoring,sysadmin]
---

The "CPU Steal time" issue is a well known phenomenon in the cloud area. We've been recently hard hit by this problem, so we've decided to start monitoring it.

In this article I'll explain how to easily configure an AWS CloudWatch metric in order to report it.

Content:

- [Background and disclaimer](/Monitoring-CPU-steal-time-on-aws-ec2-instances#background-and-disclaimer)
- [Procedure: preliminary information](/Monitoring-CPU-steal-time-on-aws-ec2-instances#procedure-preliminary-information)
  - [Overview](/Monitoring-CPU-steal-time-on-aws-ec2-instances#overview)
  - [Requisites](/Monitoring-CPU-steal-time-on-aws-ec2-instances#requisites)
  - [nmon and its output](/Monitoring-CPU-steal-time-on-aws-ec2-instances#nmon-and-its-output)
- [Procedure](/Monitoring-CPU-steal-time-on-aws-ec2-instances#procedure)
  - [Packages/libraries](/Monitoring-CPU-steal-time-on-aws-ec2-instances#packageslibraries)
  - [Variables](/Monitoring-CPU-steal-time-on-aws-ec2-instances#variables)
  - [Systemd unit](/Monitoring-CPU-steal-time-on-aws-ec2-instances#systemd-unit)
  - [Log rotation](/Monitoring-CPU-steal-time-on-aws-ec2-instances#log-rotation)
  - [Processing script](/Monitoring-CPU-steal-time-on-aws-ec2-instances#processing-script)
  - [Processing script scheduling](/Monitoring-CPU-steal-time-on-aws-ec2-instances#processing-script-scheduling)
- [Conclusion](/Monitoring-CPU-steal-time-on-aws-ec2-instances#conclusion)

## Background and disclaimer

This article describes how to setup CPU steal time monitoring; for an explanation of the concept, there's a [good article by Scout APM](https://scoutapm.com/blog/understanding-cpu-steal-time-when-should-you-be-worried).

However, there's a major concern underlying this concept: who is the party responsible of a given instance of (high) CPU steal time.

CPU steal time is, in a way, a bit of a dangerous concept, because it's caused by one of two, in a sense opposite, parties:

1. the provider, overselling the hardware;
2. the customer, exceeding the allocated resources.

In this sense, I understand (but not necessarily agree with) why AWS doesn't offer the metric - while they'd certainly receive valid complaints, they'd likely be flooded by customers misinterpreting cause #2 with cause #1.

Therefore, this article has a big disclaimer:

> **Do not assume that CPU steal time is caused by AWS overselling their hardware; the data must be analyzed before making conclusions**.

In our case, we observed that, in a stack of identically configured servers, one had a higher CPU load and was less responsive, and during the time while this was happening, there was a correlation with a higher steal time. The stack was also not particularly busy, and it was well within the limits of the instance type.

## Procedure: preliminary information

### Overview

The monitoring configuration is fairly simple:

- a Systemd unit is created and configured, which runs the `nmon` tool in background;
- a script, periodically run by `cron`, parses the data and sends it to CloudWatch.

That's all!

### Requisites

A Debian derivative is required (including Ubuntu and so on); other O/Ss can be trivially adjusted.

The script uses Ruby (which is installed as part of the procedure), however, the logic is (relatively) simple, and can be adjusted to any language.

All the commands need to be run as root, and in a single session (since variables are reused).

For simplicity, don't use any character that requires quoting in the variables; in addition to being nonstandard and requiring boilerplate quoting functions, Systemd units have different escaping specifications (see `systemd-escape` program).  
Variables quoting is used nonetheless, in order to allow a clean static analysis of the script (commands).

### nmon and its output

nmon has a batch ("recording") mode, with output in CSV format:

```sh
nmon -F $filename -s $time_interval [-c $count]
```

There is no support for infinite execution. The maximum count, based on a source code review, is the int32 max (2^31 - 1 == 2147483647); higher values will cause undefined behavior, due to the `atoi` API used.

Before starting with the capture, a snapshot is taken, with the stats metadata, and some system information:

```
AAA,progname,nmon
AAA,command,nmon -s 60 -F test.log
AAA,version,16g
# ...
CPU001,CPU 1 web0-999,User%,Sys%,Wait%,Idle%,Steal%
CPU002,CPU 2 web0-999,User%,Sys%,Wait%,Idle%,Steal%
CPU_ALL,CPU Total web0-999,User%,Sys%,Wait%,Idle%,Steal%,Busy,CPUs
MEM,Memory MB web0-999,memtotal,hightotal,lowtotal,swaptotal,memfree,highfree,lowfree,swapfree,memshared,cached,active,bigfree,buffers,swapcached,inactive
# ...
BBBP,000,/etc/release
BBBP,001,/etc/release,"DISTRIB_ID=Ubuntu"
# ...
BBBP,132,/proc/cpuinfo
BBBP,133,/proc/cpuinfo,"processor	: 0"
BBBP,134,/proc/cpuinfo,"vendor_id	: GenuineIntel"
BBBP,135,/proc/cpuinfo,"cpu family	: 6"
# ...
```

There are different stat groups; for any snapshot, each group is dumped on a line, whose first field is the group name (`CPU_ALL` is needed in our case):

```
# ...
CPU_ALL,T0003,42.5,1.8,0.0,50.0,5.8,,2
CPUUTIL_ALL,T0003,84.98,0.00,3.50,99.97,0.00,0.00,0.00,11.50,0.00,0.00
CPUUTIL000,T0003,0.00,0.00,0.00,99.97,0.00,0.00,0.00,0.50,0.00,0.00
CPUUTIL001,T0003,84.98,0.00,3.50,0.00,0.00,0.00,0.00,11.50,0.00,0.00
MEM,T0003,7860.5,-0.0,-0.0,0.0,6787.5,-0.0,-0.0,0.0,-0.0,580.6,688.9,-1.0,63.2,0.0,246.3
VM,T0003,57,0,0,1740,28948,-1,0,0,0,0,0,0,0,131,0,0,0,0,0,0,0,0,0,132,0,0,0,0,0,0,0,0,0,0,0,0,0
# ...
ZZZZ,T0004,11:26:11,20-OCT-2020
```

The name of the corresponding fields are stored in the pre-capture snapshot.

The timestamp, whose group name is `ZZZZ`, is a bit confusing: does a timestamp line belong to the previous snapshot (which would justify the name), or the following?  
Since `nmon -f -c 1` prints the labels section, with a timestamp line, then a data section, it can be deduced that the timestamp belongs to the section following it.

## Procedure

### Packages/libraries

Install nmon and Ruby:

```sh
apt update && apt install --yes nmon ruby
```

Then, install the CloudWatch SDK library:

```sh
gem install aws-sdk-cloudwatch
```

### Variables

```sh
stats_path=/var/lib/nmon/recording.log
stats_interval=60 # seconds
nmon_location=$(which nmon)
processing_script_name=/opt/nmon_processing/send_nmon_stats_to_aws

# In some SDKs, the instance region can't be gathered programmatically
#
aws_region=eu-west-1
```

### Systemd unit

We configure a System unit, so that the system takes care of running it on boot, but also to handle (hypothetical) failures.

```sh
mkdir -p "$(dirname $stats_path)"

cat > /etc/systemd/system/nmon.service <<UNIT
[Unit]
Description=Nmon system stats recording

[Service]
Type=forking

StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=nmon

ExecStart=$nmon_location -F $stats_path -s $stats_interval -c 2147483647
ExecReload=/bin/kill -HUP \$MAINPID

Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable nmon
systemctl start nmon
```

The configuration is fairly simple. The major tweak is that we send stdout and stderr to the syslog, and we assign a program name (`Syslogidentifier`). This is just good practice in terms of system logging; using a program name allows sysadmins to separate a program's logs, if required.

There are alternative, valid, options for the `Restart` parameter. `on-failure` is also appropriate; for conceptual consistency with the fact that nmon will necessarily [stop at some point](#nmon-and-its-output), `always` is used, although, (2**32 - 1) cycles, even with one run per second, take almost a lifetime.

Note that, in case of restart, nmon will overwrite the existing log. Given the (supposed) rarity of the event, and the fact that the loss is minimal (the processing scripts sends the result every minute, so the past can be discarded), we don't need to handle this occurrence.

### Log rotation

Since this monitoring is assumed to be permanent, we need to manage the logs. The logrotate standard tool will take care of this.

Note that, for simplicity, we don't care about race conditions; after each rotation, the processing script can find an empty file, and miss one stat. My personal approach is that one missed stat on 1440 is not worth increasing complexity.

```sh
cat > /etc/logrotate.d/nmon <<LOGROTATE
$stats_path {
  rotate 12
  monthly
  compress
  missingok
  notifempty
}
LOGROTATE
```

This is a 100% standard logrotate configuration file, so there's nothing notable.

### Processing script

This is a production script, so it needs to be solid; at the same time, for the sake of simplicity, we ignore potential edge cases (while still documenting them).

Something very important to consider is the metric name. Once the first metric is sent to AWS, if the metric is subsequently removed, it will (currently) take 15 months for the previous metric to be removed (although it won't cost anything, if unused).  
The current namespace name follows the AWS standard, although it will be separated into "Custom Namespaces".

```sh
mkdir -p "$(dirname "$processing_script_name")"

cat > "$processing_script_name" <<'RUBY'
#!/usr/bin/env ruby

require 'time'

require 'aws-sdk-cloudwatch'

class NmonCpuStealProcessor
  METRIC_NAMESPACE = "EC2/Per-Instance Metrics"
  METRIC_NAME = "CPUStealTime"

  def initialize(aws_region, log_filename, stats_interval)
    @aws_region = aws_region
    @log_filename = log_filename
    @stats_interval = stats_interval
  end

  def execute
    stat_timestamp, steal_time = extract_latest_steal_time

    if steal_time && recent_enough?(stat_timestamp)
      metric_data = build_metric_data(METRIC_NAME, steal_time, stat_timestamp, "Percent")

      send_metric(METRIC_NAMESPACE, metric_data)
    end
  end

  private

  # Return [timestamp (Time), steal time (Float)].
  #
  def extract_latest_steal_time
    # nmon's output is small enough not to require only to load the log tail. Ruby doesn't natively
    # have such API, so either we need use a library, or we use `tac`, with the process output/control
    # complexity.
    #
    log_content = IO.read(@log_filename)

    # Input sample:
    #
    #   ZZZZ,T0025,11:34:39,21-OCT-2020
    #   CPU_ALL,T0025,1.5,1.0,0.0,95.4,2.1,,2
    #
    timestamp_line, cpu_all_line = log_content.scan(/^(?:ZZZZ|CPU_ALL),.*/).last(2)

    # We assume that if there is timestamp line, there is also a CPU line.
    #
    if timestamp_line
      timestamp_fields = timestamp_line.split(',')[2..3] || raise("Timestamp field not matching!: #{timestamp_line.inspect}")
      steal_time_field = cpu_all_line.split(',')[6] || raise("Steal time field not matching!: #{timestamp_line.inspect}")

      raw_timestamp = timestamp_fields.join(" ")

      stat_timestamp = Time.parse(raw_timestamp, "%T %Y-%b-%d")
      steal_time = steal_time_field.to_f

      [stat_timestamp, steal_time]
    end
  rescue Errno::ENOENT => error
    $stderr.puts "nmon processing: logfile #{@log_filename.inspect} not found"
  end

  def recent_enough?(stat_timestamp)
    # Don't be fussy about edge cases. If exactness is needed, this script needs to be stateful, by
    # storing the last processed timestamp (for example, in a file).
    #
    stat_timestamp >= Time.now - @stats_interval
  end

  def build_metric_data(metric_name, value, timestamp, unit)
    hostname = `hostname --fqdn`.strip

    [
      {
        metric_name: metric_name,
        dimensions: [
          {
            name: "Host",
            value: hostname
          }
        ],
        timestamp: timestamp,
        value: value.to_s,
        unit: unit
      }
    ]
  end

  def send_metric(metric_namespace, metric_data)
    Aws::CloudWatch::Client.new(region: @aws_region).put_metric_data(
      namespace: METRIC_NAMESPACE,
      metric_data:  metric_data,
    )
  end
end

if __FILE__ == $PROGRAM_NAME
  if ARGV.size != 3
    puts "Usage: #{File.basename($PROGRAM_NAME)} <aws_region> <log_filename> <stats_interval_secs>"
    exit
  else
    aws_region, log_filename, stats_interval = ARGV
  end

  NmonCpuStealProcessor.new(aws_region, log_filename, stats_interval.to_i).execute
end
RUBY

chmod +x "$processing_script_name"
```

### Processing script scheduling

Finally, we crate a cron job to launch the script every minute; for simplicity and clarity, we use a standard cron job template.

```sh
cat > "/etc/cron.d/$(basename "$processing_script_name")" <<CRON
SHELL=/bin/bash
PATH=/usr/bin:/usr/sbin:/sbin:/bin:/usr/local/bin

# .---------------------------- minute:       0 - 59 | every n minutes: */n | each minute from x to y: x-y
# |     .---------------------- hour:         0 - 23
# |     |     .---------------- day of month: 1 - 31
# |     |     |     .---------- month:        1 - 12 | jan,feb, ...
# |     |     |     |     .---- day of week:  0 - 7 (Sunday: 0 or 7) | sun, mon, tue, wed, thu, fri, sat
# |     |     |     |     |                   (once every x: */x, from x to y: x-y, a list: x, y, z)
# v     v     v     v     v     command to be executed

  *     *     *     *     *      root    $processing_script_name $aws_region $stats_path $stats_interval
CRON
```

That's all! cron will automatically pick up the change, and the statistics will be available in CloudWatch in a few minutes.

## Conclusion

In this article, we've seen how to build an fully custom AWS metric, in an end-to-end fashion from a systems perspective.

The code provided can be executed without any changes, and can also be used as a template for implementing other future metrics.

Happy monitoring!
