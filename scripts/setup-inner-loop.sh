#!/usr/bin/env bash
# setup-inner-loop.sh — provision the Phase 7/8 inner loop on Floci (idempotent)
#
# Creates/recreates:
#   - CodeBuild project  imageflow-build        (S3 source -> buildspec.yml)
#   - CodePipeline       imageflow-pipeline     (S3 source -> CodeBuild -> CodeDeploy)
#   - CodeDeploy         app imageflow + group imageflow-onprem (on-premises target)
#   - EC2 instance       imageflow-deploy       (real container; Floci resolves targets
#                                                via on-premises registration, NOT EC2 tags)
#   - S3 bucket          imageflow-artifacts    (source.zip + build artifact)
#
# Floci quirk baked in: CodeDeploy deployment groups target ON-PREMISES instances
# (register_on_premises_instance + tags). EC2-tag deployment groups fail with
# NoInstancesReachable. The deployment lifecycle itself is simulated by Floci —
# appspec hooks are real-AWS-correct but do not execute on the instance.
#
# Usage: ./scripts/setup-inner-loop.sh   (requires: floci env, python3, git)

set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
eval "$(floci env)"

echo "[inner-loop] creating artifact bucket"
aws s3 mb s3://imageflow-artifacts 2>/dev/null || true

echo "[inner-loop] uploading source.zip"
git archive --format=zip -o /tmp/source.zip HEAD
aws s3 cp /tmp/source.zip s3://imageflow-artifacts/source.zip --quiet

echo "[inner-loop] caching kaniko toolchain in S3"
if ! aws s3 ls s3://imageflow-artifacts/tools/kaniko-executor >/dev/null 2>&1; then
    docker create --name kaniko-extract gcr.io/kaniko-project/executor:latest >/dev/null
    docker cp kaniko-extract:/kaniko/executor /tmp/kaniko-executor
    docker rm kaniko-extract >/dev/null
    aws s3 cp /tmp/kaniko-executor s3://imageflow-artifacts/tools/kaniko-executor --quiet
fi

echo "[inner-loop] CodeBuild project: imageflow-build"
python3 - <<'PY'
import boto3
ep = "http://localhost:4566"
kw = dict(endpoint_url=ep, region_name="us-east-1", aws_access_key_id="test", aws_secret_access_key="test")
cb = boto3.client("codebuild", **kw)
try:
    cb.create_project(
        name="imageflow-build",
        description="ImageFlow API + Lambda image build (inner loop, Kaniko daemonless)",
        source={"type": "S3", "location": "imageflow-artifacts/source.zip"},
        artifacts={"type": "S3", "location": "imageflow-artifacts"},
        environment={"type": "LINUX_CONTAINER", "image": "python:3.12",
                     "computeType": "BUILD_GENERAL1_SMALL", "privilegedMode": True},
        serviceRole="arn:aws:iam::000000000000:role/CodeBuildServiceRole",
    )
    print("  project created")
except Exception as e:
    print("  project may exist:", str(e)[:80])
PY

echo "[inner-loop] CodeDeploy app + on-premises deployment group"
python3 - <<'PY'
import boto3
ep = "http://localhost:4566"
kw = dict(endpoint_url=ep, region_name="us-east-1", aws_access_key_id="test", aws_secret_access_key="test")
cd = boto3.client("codedeploy", **kw)
try:
    cd.create_application(applicationName="imageflow", computePlatform="Server")
    print("  application created")
except Exception as e:
    print("  application may exist:", str(e)[:80])
try:
    cd.register_on_premises_instance(instanceName="imageflow-ec2",
                                     iamSessionArn="arn:aws:iam::000000000000:role/CodeDeployServiceRole")
except Exception:
    pass
try:
    cd.add_tags_to_on_premises_instances(instanceNames=["imageflow-ec2"],
                                         tags=[{"Key": "Name", "Value": "imageflow-deploy"}])
except Exception:
    pass
try:
    cd.create_deployment_group(
        applicationName="imageflow",
        deploymentGroupName="imageflow-onprem",
        serviceRoleArn="arn:aws:iam::000000000000:role/CodeDeployServiceRole",
        deploymentConfigName="CodeDeployDefault.AllAtOnce",
        onPremisesInstanceTagFilters=[{"Type": "KEY_AND_VALUE", "Key": "Name", "Value": "imageflow-deploy"}],
        autoRollbackConfiguration={"enabled": True,
                                   "events": ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_REQUEST"]},
    )
    print("  deployment group created")
except Exception as e:
    print("  deployment group may exist:", str(e)[:80])
PY

echo "[inner-loop] CodePipeline: imageflow-pipeline"
python3 - <<'PY'
import boto3
ep = "http://localhost:4566"
kw = dict(endpoint_url=ep, region_name="us-east-1", aws_access_key_id="test", aws_secret_access_key="test")
cp = boto3.client("codepipeline", **kw)
pipe = {
    "name": "imageflow-pipeline",
    "roleArn": "arn:aws:iam::000000000000:role/CodePipelineServiceRole",
    "artifactStore": {"type": "S3", "location": "imageflow-artifacts"},
    "stages": [
        {"name": "Source", "actions": [{
            "name": "Source",
            "actionTypeId": {"category": "Source", "owner": "AWS", "provider": "S3", "version": "1"},
            "configuration": {"S3Bucket": "imageflow-artifacts", "S3ObjectKey": "source.zip",
                              "PollForSourceChanges": "false"},
            "outputArtifacts": [{"name": "SourceArtifact"}],
        }]},
        {"name": "Build", "actions": [{
            "name": "Build",
            "actionTypeId": {"category": "Build", "owner": "AWS", "provider": "CodeBuild", "version": "1"},
            "configuration": {"ProjectName": "imageflow-build"},
            "inputArtifacts": [{"name": "SourceArtifact"}],
            "outputArtifacts": [{"name": "BuildArtifact"}],
        }]},
        {"name": "Deploy", "actions": [{
            "name": "Deploy",
            "actionTypeId": {"category": "Deploy", "owner": "AWS", "provider": "CodeDeploy", "version": "1"},
            "configuration": {"ApplicationName": "imageflow", "DeploymentGroupName": "imageflow-onprem"},
            "inputArtifacts": [{"name": "BuildArtifact"}],
        }]},
    ],
}
try:
    cp.create_pipeline(pipeline=pipe)
    print("  pipeline created")
except Exception as e:
    print("  pipeline may exist:", str(e)[:80])
PY

echo "[inner-loop] done. Trigger with:"
echo "  python3 -c \"import boto3; cp=boto3.client('codepipeline',endpoint_url='http://localhost:4566',region_name='us-east-1',aws_access_key_id='test',aws_secret_access_key='test'); print(cp.start_pipeline_execution(name='imageflow-pipeline')['pipelineExecutionId'])\""
