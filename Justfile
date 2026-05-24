VM := "nixos-cloud"
KEY := "~/.ssh/local_vm"

GCS_BUCKET := env_var_or_default("GCS_BUCKET", "")
GCP_PROJECT := env_var_or_default("GCP_PROJECT", "")

S3_BUCKET := env_var_or_default("S3_BUCKET", "")
AWS_REGION := env_var_or_default("AWS_REGION", "us-east-1")

default:
    @just --list

# === inspection ===

# list all libvirt domains
ls:
    virsh -c qemu:///system list --all

# show the VM's IP
ip name=VM:
    virsh -c qemu:///system domifaddr {{name}}

# ssh into the running VM
ssh name=VM user="mcmoodoo":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{name}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{name}} running?"
      exit 1
    fi
    ssh -A -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i {{KEY}} "{{user}}@$ip"

# === image ===

# build the qcow2 from the flake
build name=VM:
    rm -f {{name}}.qcow2 result
    nix build .#nixosConfigurations.nixos-vm.config.system.build.qcow2 --no-link --print-out-paths \
      | xargs -I{} cp {}/nixos.qcow2 {{name}}.qcow2
    chmod 644 {{name}}.qcow2

# delete the local qcow2
clean name=VM:
    rm -f {{name}}.qcow2

# === domain ===

# define & start the VM from the existing qcow2 (run `just build` first if missing)
up name=VM:
    #!/usr/bin/env bash
    set -euo pipefail
    disk="{{name}}.qcow2"
    if [ ! -f "$disk" ]; then
      echo "Missing disk: $disk — run 'just build' first"
      exit 1
    fi
    virt-install \
      --connect qemu:///system \
      --name "{{name}}" \
      --ram 8192 --vcpus 2 \
      --import \
      --disk path="$disk",format=qcow2 \
      --os-variant nixos-unstable \
      --network network=default \
      --graphics none --video virtio \
      --noautoconsole

# graceful power-off (domain stays defined; use `start` to bring back)
stop name=VM:
    virsh -c qemu:///system shutdown {{name}}

# force power-off (domain stays defined)
kill name=VM:
    virsh -c qemu:///system destroy {{name}}

# power on a previously defined VM
start name=VM:
    virsh -c qemu:///system start {{name}}

# stop & undefine the VM (qcow2 stays)
down name=VM:
    -virsh -c qemu:///system destroy {{name}}
    -virsh -c qemu:///system undefine {{name}} --nvram

# down + delete the qcow2
nuke name=VM: (down name) (clean name)

# nuke + build + up — guaranteed clean slate
fresh name=VM: (nuke name) (build name) (up name)

# === gce ===

# build the GCE raw tarball (prints store path containing nixos-image-*.raw.tar.gz)
build-gce:
    nix build .#nixosConfigurations.nixos-gce.config.system.build.googleComputeImage \
      --no-link --print-out-paths

# upload the tarball to GCS and register it as a GCE image
publish-gce:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${GCS_BUCKET:?set GCS_BUCKET}"
    : "${GCP_PROJECT:?set GCP_PROJECT}"
    out=$(nix build .#nixosConfigurations.nixos-gce.config.system.build.googleComputeImage \
            --no-link --print-out-paths)
    tarball=$(ls "$out"/*.tar.gz | head -n1)
    name="nixos-$(date +%Y%m%d-%H%M%S)"
    echo "uploading $tarball -> gs://$GCS_BUCKET/$name.tar.gz"
    gsutil cp "$tarball" "gs://$GCS_BUCKET/$name.tar.gz"
    gcloud compute images create "$name" \
      --project="$GCP_PROJECT" \
      --source-uri="gs://$GCS_BUCKET/$name.tar.gz" \
      --family=nixos
    echo "created image: $name (family=nixos)"

# launch a GCE instance from the latest image in the nixos family
launch-gce instance="my-bastion" zone="us-central1-a" machine="e2-standard-2":
    #!/usr/bin/env bash
    set -euo pipefail
    : "${GCP_PROJECT:?set GCP_PROJECT}"
    gcloud compute instances create {{instance}} \
      --project="$GCP_PROJECT" \
      --zone={{zone}} \
      --machine-type={{machine}} \
      --image-family=nixos \
      --image-project="$GCP_PROJECT"

# === ec2 ===

# build the EC2 VHD (prints store path containing nixos-amazon-image-*.vhd)
build-ec2:
    nix build .#nixosConfigurations.nixos-ec2.config.system.build.amazonImage \
      --no-link --print-out-paths

# one-time: create the 'vmimport' IAM role EC2 VM Import requires (idempotent)
# the role name is fixed by AWS — ImportSnapshot looks up this literal name
setup-vmimport:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${S3_BUCKET:?set S3_BUCKET}"
    trust=$(mktemp); policy=$(mktemp)
    trap 'rm -f "$trust" "$policy"' EXIT
    # trust policy: let EC2's VM Import service assume the role (confused-deputy guard via ExternalId)
    cat > "$trust" <<'EOF'
    {
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "vmie.amazonaws.com" },
        "Action": "sts:AssumeRole",
        "Condition": { "StringEquals": { "sts:Externalid": "vmimport" } }
      }]
    }
    EOF
    # permission policy: read the AMI bucket + create/register the snapshot
    cat > "$policy" <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": ["s3:GetBucketLocation","s3:GetObject","s3:ListBucket"],
          "Resource": ["arn:aws:s3:::$S3_BUCKET","arn:aws:s3:::$S3_BUCKET/*"]
        },
        {
          "Effect": "Allow",
          "Action": ["ec2:ModifySnapshotAttribute","ec2:CopySnapshot","ec2:RegisterImage","ec2:Describe*"],
          "Resource": "*"
        }
      ]
    }
    EOF
    if aws iam get-role --role-name vmimport >/dev/null 2>&1; then
      echo "role 'vmimport' exists — refreshing policy"
    else
      echo "creating role 'vmimport'"
      aws iam create-role --role-name vmimport \
        --assume-role-policy-document "file://$trust" >/dev/null
    fi
    aws iam put-role-policy --role-name vmimport --policy-name vmimport \
      --policy-document "file://$policy"
    echo "done — run 'just publish-ec2'"

# upload the VHD to S3, import as snapshot, register as AMI
# prereq: run 'just setup-vmimport' once per AWS account
publish-ec2:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${S3_BUCKET:?set S3_BUCKET}"
    out=$(nix build .#nixosConfigurations.nixos-ec2.config.system.build.amazonImage \
            --no-link --print-out-paths)
    vhd=$(ls "$out"/*.vhd | head -n1)
    name="nixos-$(date +%Y%m%d-%H%M%S)"
    key="$name.vhd"
    echo "uploading $vhd -> s3://$S3_BUCKET/$key"
    aws s3 cp "$vhd" "s3://$S3_BUCKET/$key" --region "$AWS_REGION"
    echo "starting import-snapshot"
    task=$(aws ec2 import-snapshot --region "$AWS_REGION" \
            --description "$name" \
            --disk-container "Format=VHD,UserBucket={S3Bucket=$S3_BUCKET,S3Key=$key}" \
            --query 'ImportTaskId' --output text)
    echo "import task: $task — polling (5–15 min typical)"
    while :; do
      status=$(aws ec2 describe-import-snapshot-tasks --region "$AWS_REGION" \
                --import-task-ids "$task" \
                --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)
      case "$status" in
        completed) break ;;
        deleted|deleting|cancelled|cancelling) echo "import failed: $status"; exit 1 ;;
        *)
          progress=$(aws ec2 describe-import-snapshot-tasks --region "$AWS_REGION" \
                      --import-task-ids "$task" \
                      --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Progress' --output text)
          echo "  $status ($progress%)"
          sleep 30
          ;;
      esac
    done
    snap=$(aws ec2 describe-import-snapshot-tasks --region "$AWS_REGION" \
            --import-task-ids "$task" \
            --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)
    echo "snapshot: $snap — registering AMI"
    # root volume must be >= the snapshot size; derive it instead of hardcoding
    snap_gib=$(aws ec2 describe-snapshots --region "$AWS_REGION" \
                --snapshot-ids "$snap" \
                --query 'Snapshots[0].VolumeSize' --output text)
    vol_gib=$(( snap_gib > 20 ? snap_gib : 20 ))
    ami=$(aws ec2 register-image --region "$AWS_REGION" \
            --name "$name" \
            --architecture x86_64 \
            --root-device-name /dev/xvda \
            --virtualization-type hvm \
            --ena-support \
            --block-device-mappings "DeviceName=/dev/xvda,Ebs={SnapshotId=$snap,VolumeSize=$vol_gib,DeleteOnTermination=true,VolumeType=gp3}" \
            --query 'ImageId' --output text)
    echo "created AMI: $ami (name=$name)"

# list self-owned AMIs, newest first (all="1" to include non-nixos-* images)
list-amis all="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--region "$AWS_REGION" --owners self)
    [ -z "{{all}}" ] && args+=(--filters "Name=name,Values=nixos-*")
    aws ec2 describe-images "${args[@]}" \
      --query 'reverse(sort_by(Images,&CreationDate))[].{Name:Name,AMI:ImageId,Created:CreationDate,State:State}' \
      --output table

# list EC2 instances in the current region, newest first
list-ec2:
    aws ec2 describe-instances --region "$AWS_REGION" \
      --query 'reverse(sort_by(Reservations[].Instances[],&LaunchTime))[].{Name:Tags[?Key==`Name`]|[0].Value,ID:InstanceId,Type:InstanceType,State:State.Name,IP:PublicIpAddress,Launched:LaunchTime}' \
      --output table

# list EC2 keypairs in the current region
list-keys:
    aws ec2 describe-key-pairs --region "$AWS_REGION" \
      --query 'sort_by(KeyPairs,&KeyName)[].{Name:KeyName,Type:KeyType,ID:KeyPairId}' \
      --output table

# import a local public key as an EC2 keypair (private key never leaves your machine)
import-key name pubkey="~/.ssh/id_ed25519.pub":
    #!/usr/bin/env bash
    set -euo pipefail
    path=$(eval echo {{pubkey}})
    [ -f "$path" ] || { echo "public key not found: $path"; exit 1; }
    aws ec2 import-key-pair --region "$AWS_REGION" \
      --key-name "{{name}}" \
      --public-key-material "fileb://$path" \
      --query '{Name:KeyName,ID:KeyPairId}' --output table

# ssh into a running EC2 instance by Name tag (user baked into the image config)
ssh-ec2 instance="my-bastion" user="mcmoodoo":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(aws ec2 describe-instances --region "$AWS_REGION" \
          --filters "Name=tag:Name,Values={{instance}}" "Name=instance-state-name,Values=running" \
          --query 'Reservations[].Instances[].PublicIpAddress | [0]' --output text)
    if [ -z "$ip" ] || [ "$ip" = "None" ]; then
      echo "no running instance named {{instance}} with a public IP in $AWS_REGION"
      exit 1
    fi
    echo "ssh {{user}}@$ip"
    ssh -i {{KEY}} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      {{user}}@"$ip"

# launch an EC2 instance from the latest self-owned nixos-* AMI
launch-ec2 instance="nixos-test" type="t3.medium" key_name="":
    #!/usr/bin/env bash
    set -euo pipefail
    ami=$(aws ec2 describe-images --region "$AWS_REGION" --owners self \
            --filters "Name=name,Values=nixos-*" \
            --query 'sort_by(Images, &CreationDate) | [-1].ImageId' --output text)
    [ "$ami" = "None" ] && { echo "no nixos-* AMI found in $AWS_REGION"; exit 1; }
    echo "launching {{instance}} ($ami, {{type}})"
    args=(--region "$AWS_REGION" --image-id "$ami" --instance-type {{type}} \
          --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value={{instance}}}]")
    [ -n "{{key_name}}" ] && args+=(--key-name "{{key_name}}")
    aws ec2 run-instances "${args[@]}" \
      --query 'Instances[0].[InstanceId,PublicIpAddress]' --output text

# terminate a running/stopped EC2 instance by Name tag (deletes it + its root EBS volume)
terminate-ec2 instance="my-bastion":
    #!/usr/bin/env bash
    set -euo pipefail
    ids=$(aws ec2 describe-instances --region "$AWS_REGION" \
            --filters "Name=tag:Name,Values={{instance}}" \
                      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query 'Reservations[].Instances[].InstanceId' --output text)
    if [ -z "$ids" ]; then
      echo "no live instance named {{instance}} in $AWS_REGION"
      exit 0
    fi
    echo "terminating: $ids"
    aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids $ids \
      --query 'TerminatingInstances[].{ID:InstanceId,State:CurrentState.Name}' --output table

# === day-2 ===

# apply config changes to the running VM in-place via SSH
switch name=VM user="mcmoodoo":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{name}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{name}} running?"
      exit 1
    fi
    NIX_SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i {{KEY}}" \
      nixos-rebuild switch --flake .#nixos-vm \
      --target-host "{{user}}@$ip" \
      --sudo
