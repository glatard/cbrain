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


# For Bourreaux with ScirOpenStack and ScirAmazon cluster types
# This class associates a Disk Image Bourreau to an disk image id and image type. 

class DiskImageConfig < ActiveRecord::Base

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  belongs_to     :bourreau   
  belongs_to     :disk_image_bourreau 

  attr_accessible :bourreau_id, :disk_image_bourreau_id, :disk_image_id, :instance_type, :user_name, :task_slots, :boot_timeout, :ssh_tunnel_port, :ssh_key_pair

end
