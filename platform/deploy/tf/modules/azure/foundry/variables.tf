variable "account_name" {
  description = "Globally unique Microsoft Foundry account name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$", var.account_name))
    error_message = "account_name must contain 2-64 lowercase letters, numbers, or hyphens, and must start and end with a letter or number."
  }
}

variable "location" {
  description = "Azure region that hosts the Microsoft Foundry account."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group resource ID."
  type        = string
}

variable "project_name" {
  description = "Microsoft Foundry project name."
  type        = string
}

variable "deployment_enabled" {
  description = "Whether to deploy Claude Sonnet 5 and accept its Marketplace terms."
  type        = bool
  default     = true
}

variable "deployment_name" {
  description = "Name used by the application when it calls the deployed model."
  type        = string
  default     = "claude-sonnet-5"
}

variable "deployment_sku" {
  description = "Foundry deployment type. GlobalStandard is pay per token and uses global Azure routing."
  type        = string
  default     = "GlobalStandard"

  validation {
    condition     = contains(["GlobalStandard", "DataZoneStandard"], var.deployment_sku)
    error_message = "deployment_sku must be GlobalStandard or DataZoneStandard."
  }
}

variable "deployment_capacity" {
  description = "Deployment input-token quota in thousands of tokens per minute."
  type        = number
  default     = 25

  validation {
    condition     = var.deployment_capacity > 0 && floor(var.deployment_capacity) == var.deployment_capacity
    error_message = "deployment_capacity must be a positive whole number."
  }
}

variable "organization_name" {
  description = "Legal organization name submitted when Terraform accepts the Anthropic Marketplace terms."
  type        = string

  validation {
    condition     = trimspace(var.organization_name) != ""
    error_message = "organization_name must not be empty."
  }
}

variable "country_code" {
  description = "Two-letter ISO country code submitted with the Marketplace terms."
  type        = string

  validation {
    condition     = can(regex("^[A-Z]{2}$", var.country_code))
    error_message = "country_code must be a two-letter uppercase ISO country code."
  }
}

variable "industry" {
  description = "Industry submitted with the Marketplace terms."
  type        = string

  validation {
    condition = contains([
      "technology",
      "finance",
      "healthcare",
      "education",
      "retail",
      "manufacturing",
      "government",
      "media",
      "other",
    ], var.industry)
    error_message = "industry must be a value supported by the Microsoft Foundry Marketplace form."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "gpt_deployment_enabled" {
  description = "Whether to deploy GPT-5.4 mini, the model the platform's azure-openai provider kind reads."
  type        = bool
  default     = true
}

variable "gpt_deployment_name" {
  description = "GPT deployment name entered in the platform model-provider form."
  type        = string
  default     = "gpt-5.4-mini"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$", var.gpt_deployment_name))
    error_message = "gpt_deployment_name must be 1-64 characters of letters, numbers, dots, hyphens, or underscores, and must start with a letter or number."
  }
}

variable "gpt_deployment_sku" {
  description = "Foundry deployment type for the GPT deployment. GlobalStandard is pay per token and uses global Azure routing."
  type        = string
  default     = "GlobalStandard"

  validation {
    condition     = contains(["GlobalStandard", "DataZoneStandard"], var.gpt_deployment_sku)
    error_message = "gpt_deployment_sku must be GlobalStandard or DataZoneStandard."
  }
}

variable "gpt_deployment_capacity" {
  description = "GPT deployment input-token quota in thousands of tokens per minute."
  type        = number
  default     = 25

  validation {
    condition     = var.gpt_deployment_capacity > 0 && floor(var.gpt_deployment_capacity) == var.gpt_deployment_capacity
    error_message = "gpt_deployment_capacity must be a positive whole number."
  }
}

variable "gpt_model_version" {
  description = "Model version for the GPT deployment. Null lets Azure serve the current default version."
  type        = string
  default     = null
}
