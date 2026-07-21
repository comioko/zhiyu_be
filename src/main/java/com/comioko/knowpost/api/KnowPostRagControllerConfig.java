package com.comioko.knowpost.api;

import com.comioko.llm.rag.RagIndexService;
import com.comioko.llm.rag.RagQueryService;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 条件化注册 {@link KnowPostRagController}。
 *
 * 当 spring.ai.openai.api-key 配置时（即 AI 启用），注册 RAG controller；
 * 否则整个 controller 不进入 Spring 上下文，RAG 接口返回 404。
 *
 * 使用 {@code @ConditionalOnProperty} 而不是 {@code @ConditionalOnBean}
 * 是为了避免 bean 条件依赖时不可靠。
 */
@Configuration
@ConditionalOnProperty(name = "spring.ai.openai.api-key", matchIfMissing = false)
public class KnowPostRagControllerConfig {

    @Bean
    public KnowPostRagController knowPostRagController(RagIndexService indexService,
                                                       RagQueryService ragQueryService) {
        return new KnowPostRagController(indexService, ragQueryService);
    }
}