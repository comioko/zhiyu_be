package com.comioko.llm.rag;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import com.comioko.config.EsProperties;
import com.comioko.knowpost.mapper.KnowPostMapper;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * RAG 相关服务的条件化注册。
 *
 * 通过 {@link ConditionalOnProperty} 在 ApplicationContext 启动早期判断 spring.ai.openai.api-key
 * 是否配置（占位符解析后的真实值），避免 {@code @ConditionalOnBean} 在 {@code @Configuration}
 * 阶段对动态创建的 bean 不可靠的问题。
 *
 * ai-qa profile 启用时（key 已配置），本配置类生效，RagIndexService / RagQueryService 注册；
 * ai-qa profile 关闭时（application-prod-noai.yml 排除 spring ai autoconfigure + key 为空），
 * 本配置类不生效，整个 RAG 模块消失。
 */
@Configuration
@ConditionalOnProperty(name = "spring.ai.openai.api-key", matchIfMissing = false)
public class RagConfig {

    /**
     * 注册索引服务（依赖 VectorStore，Spring AI 自动装配保证其存在）。
     */
    @Bean
    @ConditionalOnBean(VectorStore.class)
    public RagIndexService ragIndexService(VectorStore vectorStore,
                                          KnowPostMapper knowPostMapper,
                                          ElasticsearchClient es,
                                          EsProperties esProps) {
        return new RagIndexService(vectorStore, knowPostMapper, es, esProps);
    }

    /**
     * 注册查询服务（依赖 VectorStore + ChatClient）。
     */
    @Bean
    @ConditionalOnBean({VectorStore.class, ChatClient.class})
    public RagQueryService ragQueryService(VectorStore vectorStore,
                                          ChatClient chatClient,
                                          RagIndexService ragIndexService) {
        return new RagQueryService(vectorStore, chatClient, ragIndexService);
    }
}