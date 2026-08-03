# Azure billing alerts

The Azure stack owns the billing-profile cost guardrails in
`azure/billing-alerts.tf`. They run in Azure and do not depend on an operator's
computer.

## Coverage

- A CAD 200 monthly budget alerts on actual and forecast spend at 75%, 90%,
  100%, and 120%.
- A CAD 2,800 grant-term budget alerts on actual and forecast spend at 80%,
  90%, and 100% through the current credit expiry on June 27, 2027.
- Both enabled billing-profile subscriptions have daily cost-anomaly alerts.
- A billing-profile Cost Management report emails month-to-date cost, forecast,
  budget status, and a CSV every Monday at 16:00 UTC.

The budgets cover every subscription attached to billing profile
`MD5W-UT2A-BG7-PGB`. Alert email is sent directly to the billing profile's
invoice address.

These resources use the AzAPI provider because AzureRM does not expose
billing-profile Cost Management budgets, views, or scheduled actions. Import
blocks adopt the pre-existing live resources during the first Terraform apply.
`prevent_destroy` protects the alerting resources from accidental removal.

## Bootstrap access

The infrastructure service principal needs the `Billing profile contributor`
role on the billing profile. Subscription Contributor alone is insufficient
because the budgets and weekly report are billing-profile resources. This role
is a one-time bootstrap prerequisite and is intentionally not self-managed by
Terraform; it cannot grant or revoke billing access.

## Grant renewal

The budget amounts and end dates describe the current USD 2,000 nonprofit grant
term. When Microsoft renews the grant:

1. Verify the new credit lot, balance, and expiry in Azure Cost Management.
2. Recalculate the CAD monthly sustainable spend with the desired reserve.
3. Update both budgets and extend the weekly scheduled action. Azure permits a
   Cost Management email schedule of at most one year.
4. Run a Terraform plan and confirm the live alert recipients and thresholds.

Budget alerts notify but do not stop resources. Both subscriptions currently
have their Azure spending limits disabled, so preventing paid usage requires a
separate availability decision.
