output "detector_id" {
  description = "The ID of the GuardDuty detector"
  value       = aws_guardduty_detector.detector.id
}
