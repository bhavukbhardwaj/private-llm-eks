variable "repository_names" {
  description = "Names of the private ECR repositories to create (mirrors of upstream images)."
  type        = list(string)
}

variable "keep_last_images" {
  description = "How many images to keep per repository; older ones are expired to limit storage cost."
  type        = number
  default     = 5
}

variable "force_delete" {
  description = "Delete repositories even if they still contain images (sandbox teardown only)."
  type        = bool
  default     = true
}
