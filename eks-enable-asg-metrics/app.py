from aws_cdk import (
    App,
    Stack,
    RemovalPolicy,
    Duration,
    aws_events as events,
    aws_lambda as lambda_,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_iam as iam
)
from constructs import Construct


class EKSASGMetricsCollectionStack(Stack):
    def __init__(self, app: App, id: str) -> None:
        super().__init__(app, id)

        
        lambda_role = iam.Role(self, "EnableASGMetricsCollectionRole",
        assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"))

        lambda_role.add_to_policy(iam.PolicyStatement(
            effect = iam.Effect.ALLOW,
            resources = ['*'],
            actions = ['eks:DescribeNodegroup',
          'autoscaling:EnableMetricsCollection'],
        ))

        lambda_role.add_managed_policy(iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"))



        # Lambda Function
        with open("lambda-handler.py", encoding="utf8") as fp:
            handler_code = fp.read()

        lambdaFn = lambda_.Function(
            self, "EnableASGMetricsCollection",
            code=lambda_.InlineCode(handler_code),
            handler="index.lambda_handler",
            timeout=Duration.seconds(600),
            runtime=lambda_.Runtime.PYTHON_3_9,
            role = lambda_role
        )

        # Set Lambda Logs Retention and Removal Policy
        logs.LogGroup(
            self,
            'logs',
            log_group_name = f"/aws/lambda/{lambdaFn.function_name}",
            removal_policy = RemovalPolicy.DESTROY,
            retention = logs.RetentionDays.ONE_DAY
        )

        # EventBridge Rule
        rule = events.Rule(
            self, "CreateNodegroupRule",
        )
        rule.add_event_pattern(
            source=["aws.eks"],
            detail_type=["AWS API Call via CloudTrail"],
            detail={'eventName': ["CreateNodegroup"],'eventSource': ["eks.amazonaws.com"]}
        )
        rule.add_target(targets.LambdaFunction(lambdaFn))


app = App()
EKSASGMetricsCollectionStack(app, "EKSASGMetricsCollection")
app.synth()