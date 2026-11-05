{{- define "devflow.labels" -}}
app.kubernetes.io/part-of: devflow
app.kubernetes.io/managed-by: {{ .Release.Service }}
devflow/environment: {{ .Values.environment }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
