{{/*
Expand the name of the chart.
*/}}
{{- define "forgetasks.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "forgetasks.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "forgetasks.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common standard labels
*/}}
{{- define "forgetasks.labels" -}}
helm.sh/chart: {{ include "forgetasks.chart" . }}
app.kubernetes.io/name: {{ include "forgetasks.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: forgeops
forgeops.dev/environment: {{ .Values.environment | default "dev" }}
{{- end }}

{{/*
API Workload Labels
*/}}
{{- define "forgetasks.api.labels" -}}
{{ include "forgetasks.labels" . }}
app.kubernetes.io/name: {{ include "forgetasks.name" . }}-api
app.kubernetes.io/component: backend
{{- end }}

{{/*
API Selector labels (immutable for Deployment matchLabels)
*/}}
{{- define "forgetasks.api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "forgetasks.name" . }}-api
app.kubernetes.io/component: backend
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
PostgreSQL Workload Labels
*/}}
{{- define "forgetasks.postgres.labels" -}}
{{ include "forgetasks.labels" . }}
app.kubernetes.io/name: {{ include "forgetasks.name" . }}-postgres
app.kubernetes.io/component: database
{{- end }}

{{/*
PostgreSQL Selector labels (immutable for StatefulSet matchLabels)
*/}}
{{- define "forgetasks.postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "forgetasks.name" . }}-postgres
app.kubernetes.io/component: database
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API Image reference calculation with strict staging fail-closed enforcement
*/}}
{{- define "forgetasks.api.image" -}}
{{- if eq .Values.environment "staging" -}}
  {{- if or (not .Values.api.image.digest) (eq .Values.api.image.digest "") -}}
    {{- fail "Staging environment strictly requires an immutable image digest (sha256:<64-hex>). Empty or tag-based image references are forbidden." -}}
  {{- end -}}
  {{- printf "%s@%s" .Values.api.image.repository .Values.api.image.digest -}}
{{- else -}}
  {{- if and .Values.api.image.digest (ne .Values.api.image.digest "") -}}
    {{- printf "%s@%s" .Values.api.image.repository .Values.api.image.digest -}}
  {{- else -}}
    {{- if or (not .Values.api.image.tag) (eq .Values.api.image.tag "") -}}
      {{- fail "A valid image tag or digest must be specified for the API workload in development." -}}
    {{- end -}}
    {{- printf "%s:%s" .Values.api.image.repository .Values.api.image.tag -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
PostgreSQL Image reference calculation with fail-closed verification
*/}}
{{- define "forgetasks.postgres.image" -}}
{{- if and .Values.postgresql.image.digest (ne .Values.postgresql.image.digest "") -}}
  {{- printf "%s@%s" .Values.postgresql.image.repository .Values.postgresql.image.digest -}}
{{- else -}}
  {{- if or (not .Values.postgresql.image.tag) (eq .Values.postgresql.image.tag "") -}}
    {{- fail "A valid image tag or digest must be specified for the PostgreSQL workload." -}}
  {{- end -}}
  {{- printf "%s:%s" .Values.postgresql.image.repository .Values.postgresql.image.tag -}}
{{- end -}}
{{- end }}
