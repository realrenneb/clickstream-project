# Day 6 Variables
variable "alert_email" {
  description = "Email for pipeline alerts"
  type        = string
  default     = "renneb@hotmail.co.uk"  # UPDATE THIS!
}

variable "glue_job_schedule" {
  description = "Schedule for Glue ETL job"
  type        = string
  default     = "rate(2 hours)"
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "50"
}
