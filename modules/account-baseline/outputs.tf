output "detector_id" {
  description = "The ID of the GuardDuty detector"
  value       = var.manage_guardduty ? aws_guardduty_detector.detector[0].id : ""
}
