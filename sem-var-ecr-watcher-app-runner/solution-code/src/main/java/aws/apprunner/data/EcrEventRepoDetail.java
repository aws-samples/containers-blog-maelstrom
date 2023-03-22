package aws.apprunner.data;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.Getter;
import lombok.Setter;
import lombok.ToString;

/**
 * Data class for extract ECR repository detail from ECR event
 */
@Data
@Setter
@Getter
@AllArgsConstructor
@ToString
public class EcrEventRepoDetail {
	private String accountId;
	private String region;
	private String repositoryName;
	private String imageTag;
}
