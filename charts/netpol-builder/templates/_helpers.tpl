{{/*
===============================================================================
 SERVICE PARSER
===============================================================================
*/}}
{{- define "netpol.parseService" -}}
{{- if eq . "any" -}}
{"any": true}
{{- else -}}
{{- $parts := splitList "/" . }}
{"port": {{ index $parts 0 }} , "protocol": "{{ upper (index $parts 1) }}"}
{{- end -}}
{{- end -}}


{{/*
===============================================================================
 DST TYPE
===============================================================================
*/}}
{{- define "netpol.dstType" -}}
{{- if .cidr -}}cidr
{{- else if .fqdn -}}fqdn
{{- else if and .namespace .workload -}}service
{{- else if .any -}}any
{{- else -}}unknown
{{- end -}}
{{- end -}}


{{/*
===============================================================================
 SRC TYPE
===============================================================================
*/}}
{{- define "netpol.srcType" -}}
{{- if .any -}}any
{{- else if and .namespace .workload -}}service
{{- else if .namespace -}}namespace
{{- else -}}unknown
{{- end -}}
{{- end -}}


{{/*
===============================================================================
 MATCH LABELS
===============================================================================
*/}}
{{- define "netpol.matchLabels" -}}
matchLabels:
{{- range $k, $v := . }}
  {{ $k }}: "{{ $v }}"
{{- end }}
{{- end -}}


{{/*
===============================================================================
 FIXED WORKLOAD SELECTOR (no extra blank lines)
===============================================================================
*/}}
{{- define "netpol.workloadSelector" -}}
{{- $root := .root -}}
{{- $token := .token -}}
{{- $selectors := $root.Values.selectors | default dict -}}

{{- if hasKey $selectors $token -}}
{{ include "netpol.matchLabels" (index $selectors $token).matchLabels | trim }}
{{- else -}}
{{ include "netpol.matchLabels" (dict "app" $token) | trim }}
{{- end -}}
{{- end -}}


{{/*
===============================================================================
 CIDR CHECK
===============================================================================
*/}}
{{- define "netpol.isCIDR" -}}
{{- if and (typeIs "string" .) (regexMatch "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+(/(3[0-2]|[12]?[0-9]))?$" .) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}


{{/*
===============================================================================
 FQDN CHECK
===============================================================================
*/}}
{{- define "netpol.isFQDN" -}}
{{- if and (typeIs "string" .) (regexMatch "^[A-Za-z0-9\\*][A-Za-z0-9\\*.-]*\\.[A-Za-z0-9][A-Za-z0-9.-]*$" .) }}
true
{{- else }}
false
{{- end -}}
{{- end -}}


{{/*
===============================================================================
 NAME HELPERS
===============================================================================
*/}}

{{/* Ingress name */}}

{{- define "netpol.ingressName" -}}
{{- $r := .rule -}}
{{- $ns := .ns -}}

{{- $srcNs := default $ns (get (get $r "src" | default dict) "namespace") | lower -}}
{{- $srcWl := default "any" (get (get $r "src" | default dict) "workload") | lower -}}
{{- $dstNs := default $ns $r.dst.namespace | lower -}}
{{- $dstWl := default "any" $r.dst.workload | lower -}}
{{- $svc := default "any" $r.dst.service | replace "/" "-" | replace ":" "-" | lower -}}


{{- if $r.dst.cidr }}
{{- $cidr := $r.dst.cidr | replace "." "-" | replace "/" "-" | lower -}}
{{- printf "np-ingress-to-cidr-%s-from-%s-%s-%s" $cidr $srcNs $srcWl $svc | replace "--" "-" | trimSuffix "-" -}}

{{- else if $r.dst.fqdn }}
{{- $fq := replace $r.dst.fqdn "." "-" | lower -}}
{{- printf "np-ingress-to-fqdn-%s-from-%s-%s-%s" $fq $srcNs $srcWl $svc | replace "--" "-" | trimSuffix "-" -}}

{{- else }}
{{- printf "np-ingress-to-%s-from-%s-%s-%s" $dstWl $srcNs $srcWl $svc | replace "--" "-" | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{/* Egress name */}}
{{- define "netpol.egressName" -}}
{{- $r := .rule -}}
{{- $ns := .ns -}}

{{- $src := get $r "src" | default dict -}}
{{- $srcWl := default "any" (get $src "workload") | lower -}}


{{- if $r.dst.cidr }}
{{- $cidr := $r.dst.cidr | replace "." "-" | replace "/" "-" | lower -}}
{{- printf "np-egress-from-%s-to-cidr-%s" $srcWl $cidr | replace "--" "-" | trimSuffix "-" -}}

{{- else if $r.dst.fqdn }}
{{- $fq := replace $r.dst.fqdn "." "-" | lower -}}
{{- printf "np-egress-from-%s-to-fqdn-%s" $srcWl $fq | replace "--" "-" | trimSuffix "-" -}}

{{- else if $r.dst.any }}
{{- printf "np-egress-from-%s-to-any" $srcWl -}}

{{- else }}
{{- $dstNs := default $ns $r.dst.namespace | lower -}}
{{- $dstWl := default "any" $r.dst.workload | lower -}}
{{- $svc := default "any" $r.dst.service | replace "/" "-" | replace ":" "-" | lower -}}
{{- printf "np-egress-from-%s-to-%s-%s-%s" $srcWl $dstNs $dstWl $svc | replace "--" "-" | trimSuffix "-" -}}
{{- end }}
{{- end }}


{{/*
===============================================================================
 FIXED PORT BLOCK (no blank lines under ports:)
===============================================================================
*/}}
{{- define "netpol.parsePortBlock" -}}
{{- $svc := . -}}
{{/* If service is nil or not a string → do nothing safely */}}
{{- if not (and $svc (typeIs "string" $svc)) }}
{{- /* no ports to render */}}
{{- else if eq $svc "any" }}
- {}
{{- else }}
{{- $parts := splitList "/" $svc -}}
- port: {{ index $parts 0 }}
  protocol: {{ upper (index $parts 1) }}
{{- end }}
{{- end -}}


{{/*
===============================================================================
ALLOW DNS only for workloads requiring DNS resolution
A workload is DNS-affected if:
  - it has a src.workload
  - its dst is NOT a CIDR
===============================================================================
*/}}

{{- define "netpol.dnsAffectedWorkloads" -}}
{{- $affected := dict -}}
{{- range .Values.rules }}
  {{- $src := .src.workload | default nil -}}
  {{- $dst := .dst -}}
  {{- if and $src (not $dst.cidr) }}
    {{- $_ := set $affected $src true -}}
  {{- end }}
{{- end }}
{{- toYaml $affected | nindent 0 }}
{{- end }}


{{/*
===============================================================================
Return the selector set for each DNS-affected workload
Example output:
checkout:
  demo: label
gateway:
  app: gateway
===============================================================================
*/}}

{{- define "netpol.dnsSelectorSets" -}}
{{- $root := . -}}
{{- $affected := fromYaml (include "netpol.dnsAffectedWorkloads" $root) | default dict -}}
{{- $selectors := dict -}}

{{- range $wl, $_ := $affected }}
  {{- $sel := include "netpol.getSelectorForWorkload" (dict "root" $root "token" $wl) | fromYaml -}}
  {{- $_ := set $selectors $wl $sel -}}
{{- end }}

{{- toYaml $selectors | nindent 0 }}
{{- end }}


{{/*
===============================================================================
Resolve selector for workload:
If selectors.<workload>.matchLabels exists:
    return those labels
Else:
    return: app: <workload>
===============================================================================
*/}}

{{- define "netpol.getSelectorForWorkload" -}}
{{- $root := .root -}}
{{- $token := .token -}}
{{- $map := $root.Values.selectors | default dict -}}

{{- if hasKey $map $token }}
{{- toYaml (index $map $token).matchLabels -}}
{{- else }}
{{- toYaml (dict "app" $token) -}}
{{- end }}
{{- end }}