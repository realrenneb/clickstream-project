import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *
import json

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_BUCKET', 'TARGET_BUCKET', 'DATABASE_NAME'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Set up paths
source_path = f"s3://{args['SOURCE_BUCKET']}/clickstream-data/"
target_path = f"s3://{args['TARGET_BUCKET']}/events/"

print(f"Reading from: {source_path}")
print(f"Writing to: {target_path}")

# Read JSON data from raw bucket
# Handle concatenated JSON by reading as text first
raw_df = spark.read.text(source_path + "year=*/month=*/day=*/hour=*/*.gz")

# Split concatenated JSON records
split_df = raw_df.select(
    explode(
        split(col("value"), "(?<=})\s*(?={)")
    ).alias("json_string")
)

# Parse JSON strings
parsed_df = split_df.select(
    get_json_object("json_string", "$.event_id").alias("event_id"),
    get_json_object("json_string", "$.event_type").alias("event_type"),
    get_json_object("json_string", "$.user_id").alias("user_id"),
    get_json_object("json_string", "$.session_id").alias("session_id"),
    get_json_object("json_string", "$.timestamp").alias("timestamp"),
    get_json_object("json_string", "$.processed_at").alias("processed_at"),
    get_json_object("json_string", "$.device_type").alias("device_type"),
    get_json_object("json_string", "$.browser").alias("browser"),
    get_json_object("json_string", "$.country").alias("country"),
    get_json_object("json_string", "$.properties").alias("properties_json"),
    get_json_object("json_string", "$.lambda_request_id").alias("lambda_request_id")
)

# Convert properties from JSON string to map
final_df = parsed_df.withColumn(
    "properties",
    from_json(col("properties_json"), MapType(StringType(), StringType()))
).drop("properties_json")

# Add partitioning columns from timestamp
final_df = final_df.withColumn("timestamp_parsed", to_timestamp(col("timestamp"))) \
    .withColumn("year", year("timestamp_parsed")) \
    .withColumn("month", month("timestamp_parsed")) \
    .withColumn("day", dayofmonth("timestamp_parsed"))

# Convert timestamp strings to proper timestamp type
final_df = final_df \
    .withColumn("timestamp", to_timestamp(col("timestamp"))) \
    .withColumn("processed_at", to_timestamp(col("processed_at"))) \
    .drop("timestamp_parsed")

# Remove any null event_ids (malformed records)
final_df = final_df.filter(col("event_id").isNotNull())

print(f"Total records to process: {final_df.count()}")

# Write as Parquet with partitioning
final_df.write \
    .mode("append") \
    .partitionBy("year", "month", "day") \
    .parquet(target_path)

print("ETL job completed successfully")

job.commit()