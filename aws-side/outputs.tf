output "source_servers" {
  description = "Source servers: name => private / public IP"
  value = {
    for name, inst in aws_instance.source :
    name => { private_ip = inst.private_ip, public_ip = inst.public_ip }
  }
}

output "discovery_appliance" {
  value = {
    private_ip = aws_instance.discovery.private_ip
    public_ip  = aws_instance.discovery.public_ip
  }
}

output "replication_appliance" {
  value = {
    private_ip = aws_instance.replication.private_ip
    public_ip  = aws_instance.replication.public_ip
  }
}