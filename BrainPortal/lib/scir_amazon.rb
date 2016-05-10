
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.  
#

# This is a replacement for the drmaa.rb library; this particular subclass
# of class Scir implements a dummy cluster interface that still runs
# jobs locally as standard unix subprocesses.


require 'aws-sdk-v1'

# A Scir class to handle VMs on Amazon EC2
# This class can only handle tasks of type CBRAIN::StartVM.

class ScirAmazon < ScirCloud
 
  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:
 
  def get_available_instance_types 
    # no, there's no method in the API to return such an array!
    return [ "t2.micro", "t2.small", "t2.medium", "m3.medium", "m3.large", "m3.xlarge", "m3.2xlarge", "c3.large", "c3.xlarge", "c3.2xlarge", "c3.4xlarge", "c3.8xlarge", "r3.large", "r3.xlarge", "r3.2xlarge", "r3.4xlarge", "r3.8xlarge", "g2.2xlarge", "i2.xlarge", "i2.2xlarge", "i2.4xlarge", "i2.8xlarge", "hs1.8xlarge" ]
  end

  def get_available_key_pairs(bourreau)
    keys = Array.new
    ec2 = AWS::EC2.new(:access_key_id => bourreau.amazon_ec2_access_key_id, :secret_access_key => bourreau.amazon_ec2_secret_access_key)
    region = ec2.regions[bourreau.amazon_ec2_region]
    return "Invalid region: #{bourreau.amazon_ec2_region}" unless !region.blank?	
    ec2 = region
    region.key_pairs.each { |key| keys << [key.name] }
    return keys
  end

  def get_available_disk_images(bourreau)
    images = Array.new
    ec2 = get_amazon_ec2_connection()
    ec2.images.with_owner(:self).each { |image| images << [image.name,image.id] }
    return images
  end

  class Session < Scir::Session #:nodoc:

    @state_if_missing = Scir::STATE_RUNNING

    def update_job_info_cache #:nodoc:
      @job_info_cache = {}
      ec2 = get_amazon_ec2_connection()
      ec2.instances.each do |s|
        # get status
        state = statestring_to_stateconst(s.status)
        @job_info_cache[s.id.to_s] = { :drmaa_state => state }
      end
      true
    end

    def statestring_to_stateconst(state) #:nodoc:
      return Scir::STATE_RUNNING        if state == :running
      return Scir::STATE_DONE           if state == :stopped 
      return Scir::STATE_QUEUED_ACTIVE  if state == :pending
      return Scir::STATE_FAILED         if state == :terminated
      return Scir::STATE_UNDETERMINED
    end

    def hold(jid)
      raise "Not supported"
    end

    def release(jid)
      raise "Note supported"
    end

    def suspend(jid)
      raise "Not supported"
    end

    def resume(jid)
      raise "Not supported"
    end

    def terminate(jid)
      get_vm_instance(jid).terminate
    end
    
    def get_local_ip(jid)
      return get_instance_from_cbrain_job_id(jid).private_ip_address
    end

    def queue_tasks_tot_max
      loadav = `uptime`.strip
      loadav.match(/averages?:\s*([\d\.]+)/i)
      loadtxt = Regexp.last_match[1] || "unknown"
      case CBRAIN::System_Uname
      when /Linux/i
        cpuinfo = `cat /proc/cpuinfo 2>&1`.split("\n")
        proclines = cpuinfo.select { |i| i.match(/^processor\s*:\s*/i) }
        return [ loadtxt , proclines.size.to_s ]
      when /Darwin/i
        hostinfo = `hostinfo 2>&1`.strip
        hostinfo.match(/^(\d+) processors are/)
        numproc = Regexp.last_match[1] || "unknown"
        [ loadtxt, numproc ]
      else
        [ "unknown", "unknown" ]
      end
    rescue => e
      [ "exception", "exception" ]
    end

    def get_amazon_ec2_connection()
      # connection parameters, defined in the portal
      access_key_id = Scir.cbrain_config[:amazon_ec2_access_key_id]
      secret_access_key = Scir.cbrain_config[:amazon_ec2_secret_access_key]
      amazon_ec2_region = Scir.cbrain_config[:amazon_ec2_region]
     
      # get connection
      ec2 = AWS::EC2.new(:access_key_id => access_key_id, :secret_access_key => secret_access_key)
      region = ec2.regions[amazon_ec2_region]
      raise "Region #{region} does not exist" unless region.exists?
      return region
    end

    def get_security_group(security_groups,security_group_name)
      security_groups.each do |g|
        return g if g.name == security_group_name
      end
      return false
    end

    def submit_VM(vm_name,image_id,key_pair,instance_type,tag_value)
      ec2 = get_amazon_ec2_connection()
      security_groups=ec2.security_groups
      security_group_name="cbrain worker"
      if ec2.security_groups.map{ |c| c.name }.include? security_group_name
        security_group = get_security_group security_groups,security_group_name
      else
        security_group = ec2.security_groups.create(security_group_name) 
        ip_addresses=['0.0.0.0/0']
        security_group.authorize_ingress :tcp, 22, *ip_addresses
      end
      instance = ec2.instances.create(:image_id => image_id, :instance_type => instance_type, :key_pair => ec2.key_pairs[key_pair], :security_groups => [security_group])
      (1..30).each do |i| # poor man's timer
        puts "Tagging instance"
        begin
          # may raise an exception
          instance.tag('Service', :value => tag_value)
          puts "Instance tagged"
          break
        rescue => e
          puts e.message
        end
        sleep 1
      end
      return instance
      #TODO instance name is not used
    end
    
    def run(job)
      task = CbrainTask.find(job.task_id)
      vm = submit_VM("CBRAIN Worker", task.params[:disk_image], task.params[:ssh_key_pair],task.params[:instance_type], "CBRAIN worker") 
      return vm.id.to_s
    end

    private
    
    def get_instance_from_cbrain_job_id(jid)
      cluster_jobid = CbrainTask.where(:id => jid).first.cluster_jobid
      return get_vm_instance(cluster_jobid)
    end

    def get_vm_instance(id)
      ec2 = get_amazon_ec2_connection()
      instance = ec2.instances.detect { |x| x.id == id }
      return instance
    end

    def qsubout_to_jid(txt)
      raise "Not used in this implementation."
    end

  end
  
  # This method seems required
  class JobTemplate < Scir::JobTemplate #:nodoc
    # NOTE: We use a custom 'run' method in the Session, instead of Scir's version.
    def qsub_command
      return "echo This is never executed"
    end
    
  end

end

