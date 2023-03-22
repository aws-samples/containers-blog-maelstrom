package aws.apprunner.data;

import lombok.Data;
import lombok.Getter;
import lombok.Setter;
import lombok.ToString;

/**
 * Data class to store semantic version watcher details
 */
@Data
@Setter
@Getter
@ToString
public class ServiceMatcher {
	private String repository;
	private String semVersion;
	private String serviceArn;
}
