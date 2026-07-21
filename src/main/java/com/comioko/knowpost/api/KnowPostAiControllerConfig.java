package com.comioko.knowpost.api;

import com.comioko.llm.service.KnowPostDescriptionService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 条件化注册 {@link KnowPostAiController}。
 *
 * 通过 {@code @ConditionalOnProperty} 在 Spring Environment 阶段评估
 * spring.ai.openai.api-key 是否有值，比 {@code @ConditionalOnBean} 在 bean 工厂
 * 阶段评估更可靠，避免 bean 条件相互依赖导致的"不可见"问题。
 */
@Configuration
@ConditionalOnProperty(name = "spring.ai.openai.api-key", matchIfMissing = false)
public class KnowPostAiControllerConfig {

    @Bean
    public KnowPostAiController knowPostAiController(KnowPostDescriptionService service) {
        return new KnowPostAiController(service);
    }
}