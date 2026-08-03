locals {
  billing_account_name = "2d7e7a3f-a0b0-5097-b532-10adb183776b:dcafb92e-07c4-43bc-81c8-52aa95a1f251_2019-05-31"
  billing_profile_name = "MD5W-UT2A-BG7-PGB"
  billing_profile_id   = "/providers/Microsoft.Billing/billingAccounts/${local.billing_account_name}/billingProfiles/${local.billing_profile_name}"
  billing_alert_email  = "benzhangniu@gmail.com"

  billing_subscriptions = {
    primary   = "da091416-7245-487a-a165-deb1cb35397e"
    secondary = "7f23bd80-fe8d-4f30-b22f-6e8aea70a8d4"
  }

  monthly_budget_notifications = merge(
    {
      for threshold in [75, 90, 100, 120] : "actual_${threshold}" => {
        contactEmails = [local.billing_alert_email]
        enabled       = true
        locale        = "en-us"
        operator      = "GreaterThanOrEqualTo"
        threshold     = threshold
        thresholdType = "Actual"
      }
    },
    {
      for threshold in [75, 90, 100, 120] : "forecast_${threshold}" => {
        contactEmails = [local.billing_alert_email]
        enabled       = true
        locale        = "en-us"
        operator      = "GreaterThanOrEqualTo"
        threshold     = threshold
        thresholdType = "Forecasted"
      }
    },
  )

  credit_runway_notifications = merge(
    {
      for threshold in [80, 90, 100] : "actual_${threshold}" => {
        contactEmails = [local.billing_alert_email]
        enabled       = true
        locale        = "en-us"
        operator      = "GreaterThanOrEqualTo"
        threshold     = threshold
        thresholdType = "Actual"
      }
    },
    {
      for threshold in [80, 90, 100] : "forecast_${threshold}" => {
        contactEmails = [local.billing_alert_email]
        enabled       = true
        locale        = "en-us"
        operator      = "GreaterThanOrEqualTo"
        threshold     = threshold
        thresholdType = "Forecasted"
      }
    },
  )
}

# The current USD 2,000 nonprofit grant expires on 2027-06-27. CAD 200/month
# preserves roughly 20% of its latest estimated CAD value through that date.
resource "azapi_resource" "monthly_sustainable_spend" {
  type      = "Microsoft.CostManagement/budgets@2025-03-01"
  name      = "monthly-sustainable-spend"
  parent_id = local.billing_profile_id

  body = {
    properties = {
      amount        = 200
      category      = "Cost"
      notifications = local.monthly_budget_notifications
      timeGrain     = "Monthly"
      timePeriod = {
        startDate = "2026-08-01T00:00:00Z"
        endDate   = "2027-06-27T18:52:17Z"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# CAD 2,800 approximates the grant's 2026-07-01 opening value. Forecast alerts
# at 80%, 90%, and 100% warn when continued spend threatens the credit runway.
resource "azapi_resource" "sponsorship_credit_runway" {
  type      = "Microsoft.CostManagement/budgets@2025-03-01"
  name      = "sponsorship-credit-runway"
  parent_id = local.billing_profile_id

  body = {
    properties = {
      amount        = 2800
      category      = "Cost"
      notifications = local.credit_runway_notifications
      timeGrain     = "Annually"
      timePeriod = {
        startDate = "2026-07-01T00:00:00Z"
        endDate   = "2027-06-27T18:52:17Z"
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "weekly_credit_runway_view" {
  type      = "Microsoft.CostManagement/views@2025-03-01"
  name      = "weekly-credit-runway-costs"
  parent_id = local.billing_profile_id

  body = {
    properties = {
      accumulated = "true"
      chart       = "Area"
      displayName = "Weekly credit runway costs"
      kpis = [
        {
          enabled = true
          type    = "Forecast"
        },
        {
          enabled = true
          id      = azapi_resource.monthly_sustainable_spend.id
          type    = "Budget"
        },
      ]
      metric = "ActualCost"
      pivots = [
        {
          name = "SubscriptionName"
          type = "Dimension"
        },
        {
          name = "ServiceName"
          type = "Dimension"
        },
        {
          name = "ResourceGroupName"
          type = "Dimension"
        },
      ]
      query = {
        type      = "Usage"
        timeframe = "MonthToDate"
        dataSet = {
          aggregation = {
            totalCost = {
              function = "Sum"
              name     = "Cost"
            }
          }
          granularity = "Daily"
          sorting = [
            {
              direction = "Ascending"
              name      = "UsageDate"
            },
          ]
        }
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "weekly_credit_runway_email" {
  type      = "Microsoft.CostManagement/scheduledActions@2025-03-01"
  name      = "weekly-credit-runway-costs"
  parent_id = local.billing_profile_id

  body = {
    kind = "Email"
    properties = {
      displayName = "Weekly Azure cost and forecast"
      fileDestination = {
        fileFormats = ["Csv"]
      }
      notification = {
        subject = "Azure weekly credit-runway cost report"
        to      = [local.billing_alert_email]
      }
      notificationEmail = local.billing_alert_email
      schedule = {
        daysOfWeek = ["Monday"]
        endDate    = "2027-08-02T07:59:59Z"
        frequency  = "Weekly"
        hourOfDay  = 16
        startDate  = "2026-08-03T08:00:00Z"
      }
      status = "Enabled"
      viewId = azapi_resource.weekly_credit_runway_view.id
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "daily_cost_anomaly" {
  for_each = local.billing_subscriptions

  type      = "Microsoft.CostManagement/scheduledActions@2025-03-01"
  name      = "daily-cost-anomaly"
  parent_id = "/subscriptions/${each.value}"

  body = {
    kind = "InsightAlert"
    properties = {
      displayName = "Daily cost anomaly"
      notification = {
        subject = "Azure cost anomaly detected"
        to      = [local.billing_alert_email]
      }
      schedule = {
        endDate   = "2031-08-02T23:59:59Z"
        frequency = "Daily"
        startDate = "2026-08-03T00:00:00Z"
      }
      status = "Enabled"
      viewId = "/subscriptions/${each.value}/providers/Microsoft.CostManagement/views/ms:DailyAnomalyByResourceGroup"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Adopt the Azure-native alerting resources created before they were codified.
import {
  to = azapi_resource.monthly_sustainable_spend
  id = "${local.billing_profile_id}/providers/Microsoft.CostManagement/budgets/monthly-sustainable-spend?api-version=2025-03-01"
}

import {
  to = azapi_resource.sponsorship_credit_runway
  id = "${local.billing_profile_id}/providers/Microsoft.CostManagement/budgets/sponsorship-credit-runway?api-version=2025-03-01"
}

import {
  to = azapi_resource.weekly_credit_runway_view
  id = "${local.billing_profile_id}/providers/Microsoft.CostManagement/views/weekly-credit-runway-costs?api-version=2025-03-01"
}

import {
  to = azapi_resource.weekly_credit_runway_email
  id = "${local.billing_profile_id}/providers/Microsoft.CostManagement/scheduledActions/weekly-credit-runway-costs?api-version=2025-03-01"
}

import {
  to = azapi_resource.daily_cost_anomaly["primary"]
  id = "/subscriptions/${local.billing_subscriptions.primary}/providers/Microsoft.CostManagement/scheduledActions/daily-cost-anomaly?api-version=2025-03-01"
}

import {
  to = azapi_resource.daily_cost_anomaly["secondary"]
  id = "/subscriptions/${local.billing_subscriptions.secondary}/providers/Microsoft.CostManagement/scheduledActions/daily-cost-anomaly?api-version=2025-03-01"
}
