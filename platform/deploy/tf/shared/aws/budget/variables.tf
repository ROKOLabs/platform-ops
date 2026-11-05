variable "name" {
  type = string
}

variable "limit_usd" {
  type = string
}

variable "notify_emails" {
  type = list(string)
}

variable "actual_thresholds" {
  description = "Percentages of limit that trigger alerts on ACTUAL spend"
  type        = list(number)
  default     = [80, 100]
}

variable "forecasted_thresholds" {
  description = "Percentages that trigger on FORECASTED spend - these warn early"
  type        = list(number)
  default     = [100]
}
