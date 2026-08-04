# image-processor Lambda — custom image (ADR-06)
#
# Built from the public AWS Lambda Python base so the Lambda Runtime Interface
# Client (RIC) entrypoint is available out of the box. Push to Floci ECR and
# register with: aws lambda create-function --package-type Image ...
FROM public.ecr.aws/lambda/python:3.12

COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install -r ${LAMBDA_TASK_ROOT}/requirements.txt

COPY handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
